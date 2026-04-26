import AppKit
import SwiftUI
import QuartzCore

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

// MARK: - Active spaces helper (shared logic for overview + workspace switching)

/// Compute sorted active space indices from a spaces snapshot: occupied + one extra empty at end.
func activeSpaceIndices(from spaces: [SpaceInfo], currentIndex: Int) -> [Int] {
    let lastOccupied = spaces.filter { !$0.windowIDs.isEmpty }.map(\.index).max() ?? 0
    let cutoff = max(lastOccupied, currentIndex) + 1
    return spaces.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }
        .map(\.index).sorted()
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow!
    private var hostingView: NSHostingView<OverviewView>!
    private var gestureMonitor: GestureMonitor?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let state = OverviewState()
    private var signalSource: DispatchSourceSignal?
    private var signalSource2: DispatchSourceSignal?
    private var gestureBaseProgress: CGFloat = 0
    private var gestureOffset: CGFloat = 0
    private var cachedWindows: [WindowInfo]?
    private var cachedSpaces: [SpaceInfo]?
    private var latestGestureDelta: CGFloat = 0
    private var showFullWhenReady = false

    private enum Phase { case hidden, preparing, visible, dismissing, switching, switchAnimating }
    private var phase: Phase = .hidden

    // MARK: - Workspace switch state

    private var wsActiveSpaces: [Int] = []
    private var wsFromSpace: Int = 0
    private var wsTargetSpace: Int = 0
    private var wsGestureProgress: CGFloat = 0
    private var wsDirection: Int = 0           // -1 or 1, locked at gesture start
    private var wsStartDelta: CGFloat = 0
    private var wsIsEdge: Bool = false
    private var wsAutoCompleting: Bool = false
    private var wsCurrentLayer: CALayer?
    private var wsTargetLayer: CALayer?
    private var wsRootLayer: CALayer?
    private var lastSketchybarUpdate: Double = 0
    private var lastOverviewHorizSwitch: Double = 0

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
        hostingView = hosting

        // Ensure the content view is layer-backed for CALayer workspace switching
        hosting.wantsLayer = true

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

        // MARK: Horizontal gesture — workspace switching

        gm.onThreeFingerHorizontal = { [weak self] (delta: CGFloat) in
            guard let self else { return }
            // When overview is visible, use debounced discrete switching
            if phase == .visible {
                handleOverviewHorizontalSwipe(delta)
                return
            }
            // When hidden or preparing: start workspace switch immediately on first horizontal frame
            if phase == .hidden || phase == .preparing {
                if phase == .preparing {
                    // Cancel the overview preparation — axis is horizontal, not vertical
                    phase = .hidden
                    cachedWindows = nil; cachedSpaces = nil
                    showFullWhenReady = false
                }
                beginWorkspaceSwitch(initialDelta: delta)
            } else if phase == .switching && !wsAutoCompleting {
                updateWorkspaceSwitch(delta: delta)
            }
        }

        gm.onThreeFingerHorizEnd = { [weak self] in
            guard let self else { return }
            if phase == .visible { return }
            if phase == .preparing {
                // Gesture ended during prepare before axis was decided — clean up
                phase = .hidden
                cachedWindows = nil; cachedSpaces = nil
                showFullWhenReady = false
                return
            }
            if phase == .switching && !wsAutoCompleting {
                endWorkspaceSwitch()
            }
        }

        gestureMonitor = gm
        gm.start()

        // SIGUSR1 — toggle overview
        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.toggle() }
        src.resume()
        signalSource = src

        // SIGUSR2 — space changed externally (fn+number), update composite cache
        signal(SIGUSR2, SIG_IGN)
        let src2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        src2.setEventHandler { [weak self] in
            guard let self, self.phase == .hidden else { return }
            Task { await WindowManager.cacheCurrentSpace() }
        }
        src2.resume()
        signalSource2 = src2

        // Invalidate composite cache on screen resolution change
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            WindowManager.invalidateCache()
        }

        state.wallpaper = WindowManager.loadWallpaper()

        // Cache builds lazily: captureFromComposite (called on every gesture) saves into cache.
        // First workspace switch may use wallpaper fallback for current space; after that, cached.

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

        hostingView.isHidden = false
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

    // MARK: - Overview actions

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

    /// Debounced discrete horizontal switching when overview is visible
    private func handleOverviewHorizontalSwipe(_ delta: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        if abs(delta) > 0.4 && now - lastOverviewHorizSwitch > 0.4 {
            lastOverviewHorizSwitch = now
            // In overview: swipe right (delta > 0) = next space, swipe left = previous
            // (matches old onSwipeRight → switchSpace(delta: 1) behavior)
            switchSpace(delta: delta > 0 ? 1 : -1)
        }
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

    // MARK: - Workspace switching (1:1 gesture-driven)

    private func beginWorkspaceSwitch(initialDelta: CGFloat) {
        guard let screen = NSScreen.main else {
            print("[overview] beginWorkspaceSwitch: no main screen")
            return
        }

        // Single yabai query for spaces
        let spaces = WindowManager.querySpaces()
        guard let focused = spaces.first(where: { $0.hasFocus }) else {
            print("[overview] beginWorkspaceSwitch: no focused space (yabai not responsive?)")
            return
        }
        let focusedIdx = focused.index

        let active = activeSpaceIndices(from: spaces, currentIndex: focusedIdx)
        guard let curPos = active.firstIndex(of: focusedIdx) else {
            print("[overview] beginWorkspaceSwitch: focused space \(focusedIdx) not in active set \(active)")
            return
        }

        wsActiveSpaces = active
        wsFromSpace = focusedIdx
        wsStartDelta = 0  // direct mapping: delta IS the slide position (no offset)
        wsAutoCompleting = false
        wsGestureProgress = 0

        // Direction: swipe right (delta > 0) = go to previous space (content slides right)
        //            swipe left  (delta < 0) = go to next space     (content slides left)
        let dir = initialDelta > 0 ? 1 : -1
        wsDirection = dir

        // Target = curPos - dir (swipe right -> previous in active list)
        let targetPos = curPos - dir
        if targetPos < 0 || targetPos >= active.count {
            wsIsEdge = true
            wsTargetSpace = focusedIdx
        } else {
            wsIsEdge = false
            wsTargetSpace = active[targetPos]
        }

        print("[overview] switch begin: \(wsFromSpace) -> \(wsTargetSpace) (dir=\(dir), edge=\(wsIsEdge), active=\(active))")

        // Set up CALayers
        setupSwitchLayers(screen: screen)

        // Wallpaper fallback for missing composites
        let wallpaperCG = WindowManager.loadWallpaper()?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)

        wsCurrentLayer?.contents = WindowManager.compositeCache[wsFromSpace] ?? wallpaperCG
        if !wsIsEdge {
            wsTargetLayer?.contents = WindowManager.compositeCache[wsTargetSpace] ?? wallpaperCG
            wsTargetLayer?.isHidden = false
        } else {
            wsTargetLayer?.isHidden = true
        }

        // Position layers at the current finger position (no jump when overlay appears)
        let W = screen.frame.width
        var t = initialDelta * CGFloat(dir)
        if wsIsEdge { t = t > 0 ? t * 0.3 : 0 }
        wsGestureProgress = t
        let signedOffset = t * CGFloat(dir)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wsCurrentLayer?.frame.origin.x = signedOffset * W
        if !wsIsEdge {
            wsTargetLayer?.frame.origin.x = CGFloat(-dir) * W + signedOffset * W
        }
        CATransaction.commit()

        // Show overlay with CALayers, hide SwiftUI hosting view
        overlayWindow.setFrame(screen.frame, display: false)
        hostingView.isHidden = true
        overlayWindow.alphaValue = 1
        overlayWindow.makeKeyAndOrderFront(nil)

        phase = .switching
    }

    private func setupSwitchLayers(screen: NSScreen) {
        // Clean up any existing layers
        wsRootLayer?.removeFromSuperlayer()

        let W = screen.frame.width
        let H = screen.frame.height
        let scale = screen.backingScaleFactor

        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: W, height: H)
        root.masksToBounds = true

        let current = CALayer()
        current.frame = CGRect(x: 0, y: 0, width: W, height: H)
        current.contentsScale = scale
        current.contentsGravity = .resizeAspectFill

        let target = CALayer()
        target.frame = CGRect(x: 0, y: 0, width: W, height: H)
        target.contentsScale = scale
        target.contentsGravity = .resizeAspectFill
        target.isHidden = true

        root.addSublayer(current)
        root.addSublayer(target)

        hostingView.layer?.addSublayer(root)

        wsRootLayer = root
        wsCurrentLayer = current
        wsTargetLayer = target
    }

    private func updateWorkspaceSwitch(delta: CGFloat) {
        guard phase == .switching, let screen = NSScreen.main else { return }
        let W = screen.frame.width

        let adjustedDelta = delta - wsStartDelta
        var t = adjustedDelta * CGFloat(wsDirection)

        // Rubber-band damping
        if wsIsEdge {
            t = t > 0 ? t * 0.3 : 0
        } else if t > 1.0 {
            t = 1.0 + (t - 1.0) * 0.3
        } else if t < 0 {
            t = t * 0.3
        }

        wsGestureProgress = t

        // Update layer positions without implicit animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let signedOffset = t * CGFloat(wsDirection)
        wsCurrentLayer?.frame.origin.x = signedOffset * W
        if !wsIsEdge {
            let targetBaseX: CGFloat = CGFloat(-wsDirection) * W
            wsTargetLayer?.frame.origin.x = targetBaseX + signedOffset * W
        }

        CATransaction.commit()

        // Update sketchybar indicator (throttled)
        updateSketchybarProgress(t)

        // Quick swipe detection
        let velocity = abs(gestureMonitor?.currentVelocityX ?? 0)
        if velocity > 5.0 && t > 0.05 && !wsIsEdge {
            wsAutoCompleting = true
            endWorkspaceSwitch()
        }
    }

    private func endWorkspaceSwitch() {
        guard phase == .switching, let screen = NSScreen.main else { return }
        let W = screen.frame.width

        let velocity = abs(gestureMonitor?.currentVelocityX ?? 0)
        let velocityInDirection = (gestureMonitor?.currentVelocityX ?? 0) * CGFloat(wsDirection)

        let shouldComplete: Bool
        if wsIsEdge {
            shouldComplete = false
        } else {
            shouldComplete = wsGestureProgress > 0.20 ||
                (velocityInDirection > 1.5 && wsGestureProgress > 0.03)
        }
        print("[overview] switch end: progress=\(String(format: "%.2f", wsGestureProgress)) velocity=\(String(format: "%.2f", velocityInDirection)) complete=\(shouldComplete)")

        phase = .switchAnimating

        if shouldComplete {
            // Animate to completion
            let remaining = max(0.01, 1.0 - wsGestureProgress)
            let velocityDuration = velocity > 0.1 ? remaining / velocity : 0.25
            let duration = max(0.15, min(0.30, velocityDuration))

            let targetCurrentX = CGFloat(wsDirection) * W
            let targetTargetX: CGFloat = 0

            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.phase == .switchAnimating else { return }
                // Switch space via yabai
                WindowManager.focusSpace(self.wsTargetSpace)
                // Brief delay then dismiss overlay and cache new space
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    self.tearDownSwitch()
                    Task { await WindowManager.cacheCurrentSpace() }
                }
            }

            wsCurrentLayer?.frame.origin.x = targetCurrentX
            wsTargetLayer?.frame.origin.x = targetTargetX

            CATransaction.commit()

            finalizeSketchybar(toSpace: wsTargetSpace)
        } else {
            // Bounce back
            let progress = abs(wsGestureProgress)
            let duration = max(0.15, min(0.30, Double(progress) * 0.5 + 0.1))

            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.phase == .switchAnimating else { return }
                self.tearDownSwitch()
            }

            wsCurrentLayer?.frame.origin.x = 0
            if !wsIsEdge {
                wsTargetLayer?.frame.origin.x = CGFloat(-wsDirection) * W
            }

            CATransaction.commit()

            finalizeSketchybar(toSpace: wsFromSpace)
        }
    }

    private func tearDownSwitch() {
        phase = .hidden
        wsRootLayer?.removeFromSuperlayer()
        wsRootLayer = nil
        wsCurrentLayer = nil
        wsTargetLayer = nil
        hostingView.isHidden = false
        overlayWindow.alphaValue = 0
        overlayWindow.orderOut(nil)
        wsGestureProgress = 0
        wsDirection = 0
        wsAutoCompleting = false
    }

    // MARK: - Sketchybar indicator during workspace switch

    private func updateSketchybarProgress(_ t: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSketchybarUpdate > 0.033 else { return }  // ~30fps max
        lastSketchybarUpdate = now

        guard wsFromSpace != wsTargetSpace, !wsIsEdge else { return }

        let clamped = max(0.0, min(1.0, t))
        let fromAlpha = UInt32((1.0 - clamped) * 255)
        let toAlpha = UInt32(clamped * 255)

        let fromBg = String(format: "0x%02x7aa2f7", fromAlpha)
        let toBg = String(format: "0x%02x7aa2f7", toAlpha)

        // Interpolate icon colors: active = 0x1a1b26 (dark), inactive = 0xa9b1d6 (light)
        let fromR = UInt32(Double(0x1a) + Double(0xa9 - 0x1a) * clamped)
        let fromG = UInt32(Double(0x1b) + Double(0xb1 - 0x1b) * clamped)
        let fromB = UInt32(Double(0x26) + Double(0xd6 - 0x26) * clamped)
        let toR = UInt32(Double(0xa9) + Double(0x1a - 0xa9) * clamped)
        let toG = UInt32(Double(0xb1) + Double(0x1b - 0xb1) * clamped)
        let toB = UInt32(Double(0xd6) + Double(0x26 - 0xd6) * clamped)

        let fromIcon = String(format: "0xff%02x%02x%02x", fromR, fromG, fromB)
        let toIcon = String(format: "0xff%02x%02x%02x", toR, toG, toB)

        WindowManager.runAsync([
            "sketchybar",
            "--animate", "linear", "2",
            "--set", "space.\(wsFromSpace)",
            "background.color=\(fromBg)", "icon.color=\(fromIcon)",
            "--set", "space.\(wsTargetSpace)",
            "background.color=\(toBg)", "icon.color=\(toIcon)"
        ])
    }

    private func finalizeSketchybar(toSpace: Int) {
        if toSpace == wsFromSpace && wsTargetSpace != wsFromSpace {
            // Bounce back — restore source highlight, clear target
            WindowManager.runAsync([
                "sketchybar",
                "--animate", "linear", "5",
                "--set", "space.\(wsFromSpace)",
                "background.color=0xff7aa2f7", "icon.color=0xff1a1b26",
                "--set", "space.\(wsTargetSpace)",
                "background.color=0x00000000", "icon.color=0xffa9b1d6"
            ])
        }
        // For completion, yabai's space_change event + space.sh handles the final state
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
