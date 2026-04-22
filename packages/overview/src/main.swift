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
    var blurredWallpaperCG: CGImage? = nil  // pre-blurred for window compositing
    @Published var draggedWindowID: Int? = nil
    @Published var dropTargetSpaceIndex: Int? = nil
    @Published var spaceFrames: [Int: CGRect] = [:]
    var appeared = false

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
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow?
    private var gestureMonitor: GestureMonitor?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var isVisible = false
    private let state = OverviewState()
    private var signalSource: DispatchSourceSignal?
    private var gestureBaseProgress: CGFloat = 0
    private var gestureOffset: CGFloat = 0
    private var cachedWindows: [WindowInfo]?
    private var cachedSpaces: [SpaceInfo]?
    private var isPreparing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let gm = GestureMonitor()

        // Pre-cache screenshots on first touch (before swipe direction is known)
        // Uses fast display composite on background thread (~100ms)
        gm.onPrepare = { [weak self] in
            guard let self, !isVisible, !isPreparing else { return }
            isPreparing = true
            DispatchQueue.global(qos: .userInteractive).async {
                // Refresh wallpaper from disk (instant — no SCK needed)
                var blurredWP: CGImage? = self.state.blurredWallpaperCG
                if let wp = WindowManager.loadWallpaper(),
                   let cg = wp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    blurredWP = WindowManager.blurImage(cg, radius: 40)
                    DispatchQueue.main.async {
                        self.state.wallpaper = wp
                        self.state.blurredWallpaperCG = blurredWP
                    }
                }

                let spaces = WindowManager.querySpaces()
                var windows = WindowManager.captureWindowsFast()
                let screen = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1243)

                // Composite transparent windows onto blurred wallpaper
                if let blurred = blurredWP {
                    windows = windows.map { win in
                        guard let img = win.image else { return win }
                        let composited = WindowManager.compositeWindow(
                            screenshot: img, blurredWP: blurred, frame: win.frame, screenSize: screen)
                        return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                                          space: win.space, frame: win.frame, image: composited, icon: win.icon)
                    }
                }

                DispatchQueue.main.async {
                    self.cachedSpaces = spaces
                    self.cachedWindows = windows.isEmpty ? nil : windows
                    self.isPreparing = false
                }
            }
        }

        gm.onThreeFingerVertical = { [weak self] (delta: CGFloat) in
            guard let self else { return }
            if !isVisible && delta > 0.01 {
                // Create overlay with metadata (instant), screenshots from cache or async
                createOverlay()
                gestureOffset = delta
                gestureBaseProgress = 0
            }
            if isVisible {
                let p = gestureBaseProgress + delta - gestureOffset
                state.progress = max(0, min(p, 1.2))
            }
        }

        gm.onThreeFingerEnd = { [weak self] in
            guard let self else { return }
            cachedWindows = nil; cachedSpaces = nil
            guard isVisible else { return }
            if state.progress > 0.35 {
                withAnimation(.easeOut(duration: 0.2)) { self.state.progress = 1.0 }
                state.appeared = true
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

        // Load wallpaper + blur on launch (synchronous — reads file from disk)
        if let wp = WindowManager.loadWallpaper() {
            state.wallpaper = wp
            if let cg = wp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                state.blurredWallpaperCG = WindowManager.blurImage(cg, radius: 40)
            }
        }

        print("[overview] daemon ready")
    }

    func toggle() { if isVisible { animateDismiss() } else { show() } }

    // MARK: - Show (instant for SIGUSR1)

    func show() {
        guard !isVisible else { return }
        createOverlay()
        withAnimation(.easeOut(duration: 0.3)) { state.progress = 1.0 }
        state.appeared = true
        gestureBaseProgress = 1.0
    }

    // MARK: - Create overlay instantly with yabai data, screenshots load async

    private func createOverlay() {
        guard !isVisible else { return }

        // Use cached data if ready, otherwise get metadata instantly (no screenshots)
        let allWindows: [WindowInfo]
        let spaces: [SpaceInfo]
        if let cached = cachedWindows {
            allWindows = cached
            spaces = cachedSpaces ?? WindowManager.querySpaces()
            cachedWindows = nil; cachedSpaces = nil
        } else {
            allWindows = WindowManager.queryWindowInfo()
            spaces = WindowManager.querySpaces()
        }
        guard !allWindows.isEmpty else { return }

        buildOverlay(spaces: spaces, windows: allWindows)

        // Load per-window captures only for windows that have NO screenshot yet
        // (off-screen windows). Don't replace composite crops — they preserve blur/vibrancy.
        Task { @MainActor in
            let needsCapture = state.windows.filter { $0.image == nil }.map(\.id)
            guard isVisible, !needsCapture.isEmpty else { return }
            let captured = await WindowManager.captureAllWindowsAsync()
            guard isVisible else { return }
            for newWin in captured {
                guard newWin.image != nil, needsCapture.contains(newWin.id) else { continue }
                if let idx = state.windows.firstIndex(where: { $0.id == newWin.id }) {
                    state.windows[idx] = newWin
                }
            }
        }
    }

    private func buildOverlay(spaces: [SpaceInfo], windows allWindows: [WindowInfo]) {
        guard let screen = NSScreen.main else { return }

        let lastOccupied = spaces.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
        let focusedIdx = spaces.first(where: { $0.hasFocus })?.index ?? 1
        let cutoff = max(lastOccupied, focusedIdx) + 1

        state.spaces = spaces.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
        state.currentSpaceIndex = focusedIdx
        state.windows = allWindows
        state.selectedWindowID = nil
        state.progress = 0
        state.appeared = false
        state.onSelect = { [weak self] id in self?.selectWindow(id) }
        state.onSelectSpace = { [weak self] idx in self?.selectSpace(idx) }
        state.onDismiss = { [weak self] in self?.animateDismiss() }
        state.onMoveWindow = { [weak self] wid, s in self?.moveWindow(wid, to: s) }
        state.onReorderSpace = { [weak self] f, t in self?.reorderSpace(f, to: t) }

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: OverviewView(state: state))
        hosting.frame = screen.frame
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        overlayWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }

    }

    // MARK: - Dismiss

    func animateDismiss() {
        guard isVisible else { return }
        withAnimation(.easeIn(duration: 0.2)) { state.progress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.tearDown()
        }
    }

    private func tearDown() {
        isVisible = false
        gestureBaseProgress = 0
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        state.windows = []; state.spaces = []
        state.progress = 0; state.appeared = false
        // wallpaper stays cached — refreshed on next prepare
    }

    // MARK: - Actions

    private func selectSpace(_ idx: Int) {
        animateDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { WindowManager.focusSpace(idx) }
    }

    private func selectWindow(_ id: Int) {
        animateDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { WindowManager.focusWindow(id) }
    }

    private func switchSpace(to index: Int) {
        guard isVisible, state.spaces.contains(where: { $0.index == index }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = index }
    }

    private func switchSpace(delta: Int) {
        guard isVisible else { return }
        let indices = state.spaces.map(\.index).sorted()
        guard let cur = indices.firstIndex(of: state.currentSpaceIndex) else { return }
        let next = cur + delta
        guard next >= 0, next < indices.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = indices[next] }
    }

    private func reorderSpace(_ from: Int, to: Int) {
        WindowManager.reorderSpace(from, to: to)
        let s = WindowManager.querySpaces()
        let last = s.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
        let cutoff = max(last, state.currentSpaceIndex) + 1
        withAnimation(.easeInOut(duration: 0.2)) {
            state.spaces = s.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
        }
    }

    private func moveWindow(_ wid: Int, to space: Int) {
        WindowManager.moveWindow(wid, toSpace: space)
        if let i = state.windows.firstIndex(where: { $0.id == wid }) {
            let w = state.windows[i]
            state.windows[i] = WindowInfo(id: w.id, pid: w.pid, app: w.app, title: w.title,
                                          space: space, frame: w.frame, image: nil, icon: w.icon)
        }
    }

    // MARK: - Keyboard

    @discardableResult
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
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
        default: return event  // don't swallow unhandled keys (Cmd+Tab, media keys, etc.)
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
app.delegate = delegate
app.run()
