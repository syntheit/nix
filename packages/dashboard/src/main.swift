import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    /// Single-key shortcut → host name. Built from DashboardView's host list so
    /// adding a new foyer host doesn't silently break the keymap.
    private static let hostKeyMap: [String: String] = Dictionary(
        uniqueKeysWithValues: DashboardView.allHostNames
            .compactMap { name in name.first.map { (String($0), name) } }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }

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
        window.ignoresMouseEvents = false

        let visual = NSVisualEffectView(frame: screen.frame)
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.appearance = NSAppearance(named: .darkAqua)
        visual.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: DashboardView())
        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.alphaValue = 0
        visual.addSubview(hosting)

        window.contentView = visual
        self.window = window

        // Show window with blur instantly, fade content in separately
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hosting.animator().alphaValue = 1
        }

        // Key event monitor
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                if DashboardExpansionState.shared.isOpen {
                    NotificationCenter.default.post(name: .dashboardCloseExpanded, object: nil)
                    return nil
                }
                self?.gracefulQuit()
                return nil
            }
            if let host = Self.hostKeyMap[event.charactersIgnoringModifiers ?? ""] {
                NotificationCenter.default.post(
                    name: .dashboardExpandHost, object: nil,
                    userInfo: ["host": host]
                )
                return nil
            }
            if event.characters == "p" {
                DispatchQueue.global().async { SystemBridge.togglePrivacy() }
                return nil
            }
            return event
        }

        // Handle SIGTERM (from pkill) gracefully
        signal(SIGTERM) { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func gracefulQuit() {
        guard let content = window.contentView?.subviews.first else {
            NSApp.terminate(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            content.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// Entry point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
