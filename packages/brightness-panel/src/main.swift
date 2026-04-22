import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let display = BrightnessManager()
    var panel: SystemPanel!
    var dismissTimer: Timer?
    var ipcServer: IPCServer!

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/brightness-panel/brightness.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 340, height: 96))
        panel.anchorPosition = .topRight
        panel.setContent(BrightnessView(display: display))

        ipcServer = IPCServer(path: Self.socketPath)
        ipcServer.handler = { [weak self] cmd in
            self?.handleCommand(cmd) ?? "ok"
        }
        ipcServer.start()

        installSignalHandlers()
    }

    func handleCommand(_ cmd: String) -> String {
        switch cmd {
        case "up":
            display.adjustBrightness(by: 1.0 / 16.0)
            showHUD()
        case "down":
            display.adjustBrightness(by: -1.0 / 16.0)
            showHUD()
        default:
            break
        }

        let pct = Int(display.brightness * 100)
        return "{\"brightness\":\(pct)}"
    }

    func showHUD() {
        if !panel.isVisible {
            panel.setContent(BrightnessView(display: display))
            panel.showAt(position: .topRight, passive: true)
        }
        scheduleDismiss()
    }

    func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.panel.dismiss()
        }
    }

    func installSignalHandlers() {
        signal(SIGTERM) { _ in
            unlink(AppDelegate.socketPath)
            exit(0)
        }
        signal(SIGINT) { _ in
            unlink(AppDelegate.socketPath)
            exit(0)
        }
    }
}

// MARK: - Entry Point

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty {
    fputs("usage: brightness-panel daemon|up|down\n", stderr)
    exit(1)
}

if args[0] == "daemon" {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    // Client mode: send command to running daemon
    if let response = sendIPC(args[0], socketPath: AppDelegate.socketPath) {
        print(response)
    } else {
        fputs("brightness-panel: daemon not running\n", stderr)
        exit(1)
    }
}
