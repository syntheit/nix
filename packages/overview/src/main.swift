import AppKit
import SwiftUI

// MARK: - Shared state

class OverviewState: ObservableObject {
    @Published var spaces: [SpaceInfo] = []
    @Published var windows: [WindowInfo] = []
    @Published var currentSpaceIndex: Int = 1
    @Published var selectedWindowID: Int? = nil
    @Published var progress: CGFloat = 0

    @Published var wallpaper: NSImage? = nil
    @Published var draggedWindowID: Int? = nil
    @Published var dropTargetSpaceIndex: Int? = nil
    @Published var spaceFrames: [Int: CGRect] = [:]

    var onSelect: ((Int) -> Void)?
    var onSelectSpace: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onMoveWindow: ((Int, Int) -> Void)?
    var onReorderSpace: ((Int, Int) -> Void)?

    var currentSpaceWindows: [WindowInfo] {
        windows.filter { $0.space == currentSpaceIndex }
    }
    func windows(forSpace index: Int) -> [WindowInfo] {
        windows.filter { $0.space == index }
    }
    let screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1243)

    /// Filter spaces to those with windows or within the visible cutoff range.
    func updateSpaces(_ fresh: [SpaceInfo]) {
        let lastOccupied = fresh.filter { !$0.windowIDs.isEmpty }.map(\.index).max() ?? 0
        let cutoff = max(lastOccupied, currentSpaceIndex) + 1
        spaces = fresh.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow!
    private var gestureMonitor: GestureMonitor?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let state = OverviewState()
    private var signalSource: DispatchSourceSignal?
    private var gestureBaseProgress: CGFloat = 0
    private var gestureOffset: CGFloat = 0
    private var cachedWindows: [WindowInfo]?
    private var cachedSpaces: [SpaceInfo]?
    private var latestGestureDelta: CGFloat = 0
    private var showFullWhenReady = false

    private enum Phase { case hidden, preparing, visible, dismissing }
    private var phase: Phase = .hidden

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }

        // Create persistent overlay window (hidden until needed)
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: OverviewView(state: state))
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        overlayWindow = window

        // Set up callbacks once
        state.onSelect = { [weak self] id in self?.selectWindow(id) }
        state.onSelectSpace = { [weak self] idx in self?.selectSpace(idx) }
        state.onDismiss = { [weak self] in self?.animateDismiss() }
        state.onMoveWindow = { [weak self] wid, s in self?.moveWindow(wid, to: s) }
        state.onReorderSpace = { [weak self] f, t in self?.reorderSpace(f, to: t) }

        let gm = GestureMonitor()

        // Capture composite on first touch (overlay stays hidden until capture ready)
        gm.onPrepare = { [weak self] in
            guard let self, phase == .hidden else { return }
            phase = .preparing
            if let wp = WindowManager.loadWallpaper() { state.wallpaper = wp }
            Task {
                let spaces = WindowManager.querySpaces()
                let windows = await WindowManager.captureFromComposite()
                await MainActor.run {
                    guard self.phase == .preparing else { return }
                    self.cachedSpaces = spaces
                    self.cachedWindows = windows.isEmpty ? nil : windows
                    self.phase = .hidden
                    guard self.cachedWindows != nil else { return }
                    if self.showFullWhenReady {
                        // Quick swipe completed during capture — show fully open with blur
                        self.showFullWhenReady = false
                        self.showOverlay()
                        withAnimation(.easeOut(duration: 0.3)) { self.state.progress = 1.0 }
                        self.gestureBaseProgress = 1.0
                    } else if self.latestGestureDelta > 0.01 {
                        // Gesture still active — show at progress 0, track from here
                        self.showOverlay()
                        self.gestureOffset = self.latestGestureDelta
                        self.gestureBaseProgress = 0
                    }
                }
            }
        }

        gm.onThreeFingerVertical = { [weak self] (delta: CGFloat) in
            guard let self else { return }
            latestGestureDelta = delta
            if phase == .hidden && delta > 0.01 && cachedWindows != nil {
                showOverlay()
                gestureOffset = delta
                gestureBaseProgress = 0
            }
            if phase == .visible {
                let p = gestureBaseProgress + delta - gestureOffset
                state.progress = max(0, min(p, 1.0))
            }
        }

        gm.onThreeFingerEnd = { [weak self] in
            guard let self else { return }
            let quickDelta = latestGestureDelta
            latestGestureDelta = 0
            cachedWindows = nil; cachedSpaces = nil
            guard phase == .visible else {
                if phase == .preparing && quickDelta > 0.3 {
                    // Quick swipe — let composite finish, then show with blur intact
                    showFullWhenReady = true
                } else {
                    phase = .hidden
                }
                return
            }
            if state.progress > 0.35 {
                withAnimation(.easeOut(duration: 0.2)) { self.state.progress = 1.0 }
                gestureBaseProgress = 1.0
                gestureOffset = 0
            } else {
                animateDismiss()
                gestureBaseProgress = 0
                gestureOffset = 0
            }
        }

        gm.onSwipeLeft = { [weak self] in self?.switchSpace(delta: -1) }
        gm.onSwipeRight = { [weak self] in self?.switchSpace(delta: 1) }

        gestureMonitor = gm
        gm.start()

        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.toggle() }
        src.resume()
        signalSource = src

        state.wallpaper = WindowManager.loadWallpaper()

        print("[overview] daemon ready")
    }

    func toggle() {
        if phase == .visible { animateDismiss() }
        else if phase == .hidden { show() }
    }

    // MARK: - Show (instant for SIGUSR1)

    func show() {
        guard phase == .hidden else { return }
        showOverlay()
        withAnimation(.easeOut(duration: 0.3)) { state.progress = 1.0 }
        gestureBaseProgress = 1.0
    }

    // MARK: - Show overlay with current data, reusing the persistent window

    private func showOverlay() {
        guard phase == .hidden else { return }

        let allWindows = cachedWindows ?? WindowManager.queryWindowInfo()
        let spaces = cachedSpaces ?? WindowManager.querySpaces()
        cachedWindows = nil; cachedSpaces = nil
        guard !allWindows.isEmpty else { return }

        // Update window frame in case screen resolution changed
        if let screen = NSScreen.main {
            overlayWindow.setFrame(screen.frame, display: false)
        }

        let focusedIdx = spaces.first(where: { $0.hasFocus })?.index ?? 1
        state.currentSpaceIndex = focusedIdx
        state.windows = allWindows
        state.selectedWindowID = nil
        state.progress = 0
        state.updateSpaces(spaces)

        WindowManager.run(["sketchybar", "--bar", "hidden=true"])
        overlayWindow.alphaValue = 0
        overlayWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        phase = .visible
        // GPU-accelerated fade-in (no SwiftUI re-renders)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.overlayWindow.animator().alphaValue = 1.0
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKey(event)
        }

        // Load per-window captures for off-screen windows only
        Task { @MainActor in
            let missing = state.windows.filter { $0.image == nil }.map(\.id)
            guard phase == .visible, !missing.isEmpty else { return }
            let captured = await WindowManager.captureAllWindowsAsync()
            guard phase == .visible else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                for newWin in captured {
                    guard newWin.image != nil, missing.contains(newWin.id) else { continue }
                    if let idx = state.windows.firstIndex(where: { $0.id == newWin.id }),
                       state.windows[idx].image == nil {
                        state.windows[idx].image = newWin.image
                    }
                }
            }
        }
    }

    // MARK: - Dismiss

    func animateDismiss(then action: (() -> Void)? = nil) {
        guard phase == .visible else { return }
        phase = .dismissing
        // GPU-accelerated fade-out alongside SwiftUI animation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.overlayWindow.animator().alphaValue = 0
        }
        withAnimation(.easeIn(duration: 0.2)) {
            self.state.progress = 0
        } completion: { [weak self] in
            guard let self, self.phase == .dismissing else { return }
            self.tearDown()
            action?()
        }
    }

    private func tearDown() {
        phase = .hidden
        gestureBaseProgress = 0
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        overlayWindow.alphaValue = 0
        overlayWindow.orderOut(nil)
        state.windows = []; state.spaces = []
        state.progress = 0
        WindowManager.run(["sketchybar", "--bar", "hidden=false"])
    }

    // MARK: - Actions

    private func selectSpace(_ idx: Int) {
        animateDismiss { WindowManager.focusSpace(idx) }
    }

    private func selectWindow(_ id: Int) {
        animateDismiss { WindowManager.focusWindow(id) }
    }

    private func switchSpace(to index: Int) {
        guard phase == .visible, state.spaces.contains(where: { $0.index == index }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = index }
    }

    private func switchSpace(delta: Int) {
        guard phase == .visible else { return }
        let indices = state.spaces.map(\.index).sorted()
        guard let cur = indices.firstIndex(of: state.currentSpaceIndex) else { return }
        let next = cur + delta
        guard next >= 0, next < indices.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = indices[next] }
    }

    private func reorderSpace(_ from: Int, to: Int) {
        WindowManager.reorderSpace(from, to: to)
        let s = WindowManager.querySpaces()
        withAnimation(.easeInOut(duration: 0.2)) {
            state.updateSpaces(s)
        }
    }

    private func moveWindow(_ wid: Int, to space: Int) {
        WindowManager.moveWindow(wid, toSpace: space)
        if let i = state.windows.firstIndex(where: { $0.id == wid }) {
            state.windows[i].space = space
            state.windows[i].image = nil
        }
    }

    // MARK: - Keyboard

    @discardableResult
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard phase == .visible else { return event }
        switch event.keyCode {
        case 53: animateDismiss()
        case 36: if let id = state.selectedWindowID { selectWindow(id) }
        case 123: selectNearest(.left)
        case 124: selectNearest(.right)
        case 126: selectNearest(.up)
        case 125: selectNearest(.down)
        case 18: switchSpace(to: 1); case 19: switchSpace(to: 2)
        case 20: switchSpace(to: 3); case 21: switchSpace(to: 4)
        case 23: switchSpace(to: 5); case 22: switchSpace(to: 6)
        case 26: switchSpace(to: 7); case 28: switchSpace(to: 8)
        case 25: switchSpace(to: 9); case 29: switchSpace(to: 10)
        default: return event
        }
        return nil
    }

    private enum Dir { case left, right, up, down }
    private func selectNearest(_ dir: Dir) {
        let wins = state.currentSpaceWindows
        guard !wins.isEmpty else { return }
        guard let curID = state.selectedWindowID, let cur = wins.first(where: { $0.id == curID }) else {
            state.selectedWindowID = wins.first?.id; return
        }
        let cc = CGPoint(x: cur.frame.midX, y: cur.frame.midY)
        var best: WindowInfo?, bestD: CGFloat = .infinity
        for w in wins where w.id != curID {
            let wc = CGPoint(x: w.frame.midX, y: w.frame.midY)
            let dx = wc.x - cc.x, dy = wc.y - cc.y
            let ok: Bool
            switch dir { case .left: ok = dx < -20; case .right: ok = dx > 20
                          case .up: ok = dy < -20; case .down: ok = dy > 20 }
            guard ok else { continue }
            let d = sqrt(dx*dx + dy*dy)
            if d < bestD { bestD = d; best = w }
        }
        if let b = best { state.selectedWindowID = b.id }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
_ = Unmanaged.passRetained(delegate) // prevent -O from releasing the weak app.delegate
app.delegate = delegate
app.run()
