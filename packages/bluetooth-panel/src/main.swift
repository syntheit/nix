import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = BluetoothManager()
    var panel: SystemPanel!
    var dropdown: SystemPanel!
    var ipcServer: IPCServer!

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/bluetooth-panel/bluetooth.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 560, height: 440))
        rebuildContent()

        dropdown = SystemPanel(size: NSSize(width: 252, height: 150))

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

    func rebuildDropdown() {
        dropdown.setContent(
            BluetoothDropdownView(
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
        manager.refresh()
        rebuildContent()
        panel.showCentered()
    }

    func dropdownHeight() -> CGFloat {
        var h: CGFloat = 76  // header (43) + separator (1) + settings (32)
        if manager.isPowered {
            let connected = manager.devices.filter { $0.isConnected }
            if !connected.isEmpty {
                h += 13 + CGFloat(connected.count) * 40 + CGFloat(max(0, connected.count - 1)) * 2
            }
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
                manager.refresh()
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
    fputs("usage: bluetooth-panel daemon|dropdown|toggle\n", stderr)
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
