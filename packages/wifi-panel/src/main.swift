import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = NetworkManager()
    var panel: SystemPanel!
    var ipcServer: IPCServer!

    // speedtest-cli path injected via SPEEDTEST_PATH env var
    let speedtestPath: String = ProcessInfo.processInfo.environment["SPEEDTEST_PATH"] ?? "/usr/bin/speedtest-cli"

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/wifi-panel/wifi.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 380, height: 560))
        rebuildContent()

        ipcServer = IPCServer(path: Self.socketPath)
        ipcServer.handler = { [weak self] cmd in
            self?.handleCommand(cmd) ?? "ok"
        }
        ipcServer.start()

        installSignalHandlers()
    }

    func rebuildContent() {
        panel.setContent(WiFiView(manager: manager, speedtestPath: speedtestPath))
    }

    func handleCommand(_ cmd: String) -> String {
        switch cmd {
        case "toggle":
            if panel.isVisible {
                panel.dismiss()
            } else {
                manager.requestLocationIfNeeded()
                manager.refreshCurrent()
                manager.scan()
                rebuildContent()
                panel.showCentered()
            }
        case "refresh":
            manager.refreshCurrent()
            manager.scan()
        default:
            break
        }
        return "ok"
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
        signal(SIGUSR1) { _ in
            DispatchQueue.main.async {
                let delegate = NSApp.delegate as! AppDelegate
                _ = delegate.handleCommand("toggle")
            }
        }
    }
}

// MARK: - Entry Point

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty {
    fputs("usage: wifi-panel daemon|toggle\n", stderr)
    exit(1)
}

if args[0] == "daemon" {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    if let response = sendIPC(args[0], socketPath: AppDelegate.socketPath) {
        print(response)
    } else {
        fputs("wifi-panel: daemon not running\n", stderr)
        exit(1)
    }
}
