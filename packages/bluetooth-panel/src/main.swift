import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = BluetoothManager()
    var panel: SystemPanel!
    var ipcServer: IPCServer!

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/bluetooth-panel/bluetooth.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 340, height: 420))
        rebuildContent()

        ipcServer = IPCServer(path: Self.socketPath)
        ipcServer.handler = { [weak self] cmd in
            self?.handleCommand(cmd) ?? "ok"
        }
        ipcServer.start()

        installSignalHandlers()
    }

    func rebuildContent() {
        panel.setContent(BluetoothView(manager: manager))
    }

    func handleCommand(_ cmd: String) -> String {
        switch cmd {
        case "toggle":
            if panel.isVisible {
                panel.dismiss()
            } else {
                manager.refresh()
                rebuildContent()
                panel.showCentered()
            }
        case "refresh":
            manager.refresh()
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
        // SIGUSR1 as backup toggle
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
    fputs("usage: bluetooth-panel daemon|toggle\n", stderr)
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
        fputs("bluetooth-panel: daemon not running\n", stderr)
        exit(1)
    }
}
