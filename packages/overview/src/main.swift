import AppKit
import SwiftUI

// MARK: - Shared state

class OverviewState: ObservableObject {
    @Published var spaces: [SpaceInfo] = []
    @Published var windows: [WindowInfo] = []
    @Published var currentSpaceIndex: Int = 1
    @Published var selectedWindowID: Int? = nil
    @Published var appeared = false
    @Published var progress: CGFloat = 0       // 0 = desktop, 1 = full overview

    // Drag state
    @Published var draggedWindowID: Int? = nil
    @Published var dropTargetSpaceIndex: Int? = nil
    var spaceFrames: [Int: CGRect] = [:]

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
    private var isCapturing = false
    private var gestureEndedDuringCapture = false
    private let state = OverviewState()
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        gestureMonitor = GestureMonitor()
        setupGestureCallbacks()
        gestureMonitor?.start()

        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.toggle() }
        src.resume()
        signalSource = src
        print("[overview] daemon ready")
    }

    private func setupGestureCallbacks() {
        guard let gm = gestureMonitor else { return }

        // Continuous vertical gesture — 1:1 tracking
        gm.onVerticalBegin = { [weak self] in self?.beginGesture() }
        gm.onVerticalUpdate = { [weak self] p in self?.updateGesture(progress: p) }
        gm.onVerticalEnd = { [weak self] _ in self?.endGesture() }

        // Dismiss (swipe down while overview is showing)
        gm.onDismissUpdate = { [weak self] p in
            guard let self, isVisible else { return }
            state.progress = max(0, 1 - p)
        }
        gm.onDismissEnd = { [weak self] _ in
            guard let self, isVisible else { return }
            if state.progress < 0.6 {
                animateDismiss()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { self.state.progress = 1.0 }
            }
        }

        // Horizontal swipes — switch workspace
        gm.onSwipeLeft = { [weak self] in self?.switchSpace(delta: -1) }
        gm.onSwipeRight = { [weak self] in self?.switchSpace(delta: 1) }
    }

    func toggle() { if isVisible { animateDismiss() } else { show() } }

    // MARK: - Gesture-driven show

    private func beginGesture() {
        guard !isVisible, !isCapturing else { return }
        isCapturing = true
        gestureEndedDuringCapture = false

        Task { @MainActor in
            let spaces = WindowManager.querySpaces()
            let allWindows = await WindowManager.captureAllWindows()

            let lastOccupied = spaces.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
            let focusedIdx = spaces.first(where: { $0.hasFocus })?.index ?? 1
            let cutoff = max(lastOccupied, focusedIdx) + 1

            state.spaces = spaces.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
            state.currentSpaceIndex = focusedIdx
            state.windows = allWindows
            state.selectedWindowID = nil
            state.onSelect = { [weak self] id in self?.selectWindow(id) }
            state.onSelectSpace = { [weak self] idx in self?.selectSpace(idx) }
            state.onDismiss = { [weak self] in self?.animateDismiss() }
            state.onMoveWindow = { [weak self] wid, s in self?.moveWindow(wid, to: s) }
            state.onReorderSpace = { [weak self] f, t in self?.reorderSpace(f, to: t) }

            createOverlayWindow()
            isCapturing = false

            // If gesture ended while we were capturing, resolve now
            if gestureEndedDuringCapture {
                resolveGestureEnd()
            }
        }
    }

    private func updateGesture(progress: CGFloat) {
        if !isVisible && !isCapturing {
            beginGesture()
        }
        state.progress = min(max(progress, 0), 1.0)
    }

    private func endGesture() {
        if isCapturing {
            // Capture still running — defer resolution
            gestureEndedDuringCapture = true
            return
        }
        resolveGestureEnd()
    }

    private func resolveGestureEnd() {
        guard isVisible else { return }
        if state.progress > 0.4 {
            withAnimation(.easeOut(duration: 0.25)) {
                state.progress = 1.0
            }
            state.appeared = true
        } else {
            animateDismiss()
        }
    }

    // MARK: - Instant show (for SIGUSR1 toggle)

    func show() {
        guard !isVisible else { return }
        isVisible = true

        Task { @MainActor in
            let spaces = WindowManager.querySpaces()
            let allWindows = await WindowManager.captureAllWindows()
            guard isVisible else { return }

            let lastOccupied = spaces.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
            let focusedIdx = spaces.first(where: { $0.hasFocus })?.index ?? 1
            let cutoff = max(lastOccupied, focusedIdx) + 1

            state.spaces = spaces.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
            state.currentSpaceIndex = focusedIdx
            state.windows = allWindows
            state.selectedWindowID = nil
            state.onSelect = { [weak self] id in self?.selectWindow(id) }
            state.onSelectSpace = { [weak self] idx in self?.selectSpace(idx) }
            state.onDismiss = { [weak self] in self?.animateDismiss() }
            state.onMoveWindow = { [weak self] wid, s in self?.moveWindow(wid, to: s) }
            state.onReorderSpace = { [weak self] f, t in self?.reorderSpace(f, to: t) }

            createOverlayWindow()
            withAnimation(.easeOut(duration: 0.3)) {
                state.progress = 1.0
            }
            state.appeared = true
        }
    }

    private func createOverlayWindow() {
        guard overlayWindow == nil, let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        withAnimation(.easeIn(duration: 0.2)) {
            state.progress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.tearDown()
        }
    }

    private func tearDown() {
        isVisible = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        state.windows = []
        state.spaces = []
        state.progress = 0
        state.appeared = false
    }

    // MARK: - Actions

    private func selectSpace(_ spaceIndex: Int) {
        animateDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            WindowManager.focusSpace(spaceIndex)
        }
    }

    private func selectWindow(_ windowID: Int) {
        animateDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            WindowManager.focusWindow(windowID)
        }
    }

    private func switchSpace(to index: Int) {
        guard isVisible, state.spaces.contains(where: { $0.index == index }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = index }
    }

    private func switchSpace(delta: Int) {
        guard isVisible else { return }
        let indices = state.spaces.map(\.index).sorted()
        guard let curPos = indices.firstIndex(of: state.currentSpaceIndex) else { return }
        let newPos = curPos + delta
        guard newPos >= 0, newPos < indices.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.currentSpaceIndex = indices[newPos] }
    }

    private func reorderSpace(_ from: Int, to: Int) {
        WindowManager.reorderSpace(from, to: to)
        let newSpaces = WindowManager.querySpaces()
        let lastOccupied = newSpaces.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
        let cutoff = max(lastOccupied, state.currentSpaceIndex) + 1
        withAnimation(.easeInOut(duration: 0.2)) {
            state.spaces = newSpaces.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
        }
    }

    private func moveWindow(_ windowID: Int, to space: Int) {
        WindowManager.moveWindow(windowID, toSpace: space)
        if let idx = state.windows.firstIndex(where: { $0.id == windowID }) {
            let w = state.windows[idx]
            state.windows[idx] = WindowInfo(
                id: w.id, pid: w.pid, app: w.app, title: w.title,
                space: space, frame: w.frame, image: nil, icon: w.icon
            )
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isVisible else { return event }
        switch event.keyCode {
        case 53: animateDismiss()
        case 36: if let id = state.selectedWindowID { selectWindow(id) }
        case 123: selectNearest(.left)
        case 124: selectNearest(.right)
        case 126: selectNearest(.up)
        case 125: selectNearest(.down)
        case 18: switchSpace(to: 1)
        case 19: switchSpace(to: 2)
        case 20: switchSpace(to: 3)
        case 21: switchSpace(to: 4)
        case 23: switchSpace(to: 5)
        case 22: switchSpace(to: 6)
        case 26: switchSpace(to: 7)
        case 28: switchSpace(to: 8)
        case 25: switchSpace(to: 9)
        case 29: switchSpace(to: 10)
        default: break
        }
        return nil
    }

    private enum Direction { case left, right, up, down }
    private func selectNearest(_ dir: Direction) {
        let wins = state.currentSpaceWindows
        guard !wins.isEmpty else { return }
        guard let curID = state.selectedWindowID,
              let cur = wins.first(where: { $0.id == curID }) else {
            state.selectedWindowID = wins.first?.id; return
        }
        let cc = CGPoint(x: cur.frame.midX, y: cur.frame.midY)
        var best: WindowInfo? = nil, bestDist: CGFloat = .infinity
        for w in wins where w.id != curID {
            let wc = CGPoint(x: w.frame.midX, y: w.frame.midY)
            let dx = wc.x - cc.x, dy = wc.y - cc.y
            let ok: Bool
            switch dir {
            case .left: ok = dx < -20; case .right: ok = dx > 20
            case .up: ok = dy < -20; case .down: ok = dy > 20
            }
            guard ok else { continue }
            let dist = sqrt(dx*dx + dy*dy)
            if dist < bestDist { bestDist = dist; best = w }
        }
        if let best { state.selectedWindowID = best.id }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
