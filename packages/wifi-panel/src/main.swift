import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = NetworkManager()
    var panel: SystemPanel!
    var dropdown: SystemPanel!
    var ipcServer: IPCServer!

    let speedtestPath: String = ProcessInfo.processInfo.environment["SPEEDTEST_PATH"] ?? "/usr/bin/speedtest-cli"

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/wifi-panel/wifi.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 560, height: 620))
        rebuildContent()

        dropdown = SystemPanel(size: NSSize(width: 252, height: 200))

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

    func rebuildDropdown() {
        dropdown.setContent(
            WiFiDropdownView(
                manager: manager,
                onOpenSettings: { [weak self] in
                    self?.showFullPanel()
                },
                onDismiss: { [weak self] in
                    self?.dropdown.dismiss()
                }
            )
        )
    }

    func showFullPanel() {
        manager.requestLocationIfNeeded()
        manager.refreshCurrent()
        manager.scan()
        rebuildContent()
        panel.showCentered()
    }

    func dropdownHeight() -> CGFloat {
        var h: CGFloat = 76  // header (43) + separator (1) + settings (32)
        if manager.isWiFiOn {
            if manager.currentNetwork != nil {
                h += 63  // known network label (26) + row (36) + separator (1)
            }
            h += 33  // other networks (32) + separator (1)
        }
        return h
    }

    func handleCommand(_ cmd: String) -> String {
        switch cmd {
        case "dropdown":
            if dropdown.isVisible {
                dropdown.dismiss()
            } else {
                if panel.isVisible { panel.dismiss() }
                manager.refreshCurrent()
                let size = NSSize(width: 252, height: dropdownHeight())
                dropdown.setFrame(NSRect(origin: dropdown.frame.origin, size: size), display: false)
                rebuildDropdown()
                dropdown.showAt(position: .belowCursor)
            }
        case "toggle":
            if panel.isVisible {
                panel.dismiss()
            } else {
                if dropdown.isVisible { dropdown.dismiss() }
                showFullPanel()
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
                _ = delegate.handleCommand("dropdown")
            }
        }
    }
}

// MARK: - Entry Point

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty {
    fputs("usage: wifi-panel daemon|dropdown|toggle\n", stderr)
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
