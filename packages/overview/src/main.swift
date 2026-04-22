import AppKit
import SwiftUI

// MARK: - Shared state between AppDelegate and SwiftUI

class OverviewState: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int? = nil
    @Published var appeared = false
    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    var columns: Int {
        switch windows.count {
        case 1:     return 1
        case 2:     return 2
        case 3:     return 3
        case 4:     return 2
        case 5...6: return 3
        case 7...9: return 3
        default:    return 4
        }
    }
}

// MARK: - App delegate (persistent daemon)

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: NSWindow?
    private var gestureMonitor: GestureMonitor?
    private var keyMonitor: Any?
    private var isVisible = false
    private let state = OverviewState()
    private var signalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        gestureMonitor = GestureMonitor(
            onSwipeUp:   { [weak self] in self?.show() },
            onSwipeDown: { [weak self] in self?.dismiss() }
        )
        gestureMonitor?.start()

        signal(SIGUSR1, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in self?.toggle() }
        src.resume()
        signalSource = src

        print("[overview] daemon ready")
    }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    // MARK: - Show

    func show() {
        guard !isVisible else { return }
        isVisible = true

        Task { @MainActor in
            let windows = await WindowManager.captureWindows()
            guard isVisible, !windows.isEmpty else {
                isVisible = false
                return
            }
            presentOverlay(windows)
        }
    }

    private func presentOverlay(_ windows: [WindowInfo]) {
        guard let screen = NSScreen.main else { isVisible = false; return }

        state.windows = windows
        state.selectedIndex = nil
        state.appeared = false
        state.onSelect = { [weak self] id in self?.selectWindow(id) }
        state.onDismiss = { [weak self] in self?.dismiss() }

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

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
    }

    // MARK: - Dismiss

    func dismiss() {
        guard isVisible else { return }
        isVisible = false

        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }

        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.overlayWindow = nil
            self?.state.windows = []
        })
    }

    // MARK: - Selection

    private func selectWindow(_ windowID: Int) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            WindowManager.focusWindow(windowID)
        }
    }

    // MARK: - Keyboard navigation

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let cols = state.columns
        let cur = state.selectedIndex ?? 0
        switch event.keyCode {
        case 53: // Escape
            dismiss(); return nil
        case 36: // Return
            if let idx = state.selectedIndex, idx < state.windows.count {
                selectWindow(state.windows[idx].id)
            }
            return nil
        case 123: // Left
            state.selectedIndex = max(0, cur - 1)
            return nil
        case 124: // Right
            state.selectedIndex = min(state.windows.count - 1, cur + 1)
            return nil
        case 126: // Up
            let i = cur - cols
            if i >= 0 { state.selectedIndex = i }
            return nil
        case 125: // Down
            let i = cur + cols
            if i < state.windows.count { state.selectedIndex = i }
            return nil
        default:
            return nil // swallow all keyboard input while overlay is visible
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
