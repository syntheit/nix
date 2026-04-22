import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let audio = AudioManager()
    var panel: SystemPanel!
    var dismissTimer: Timer?
    var ipcServer: IPCServer!

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/volume-panel/volume.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panel = SystemPanel(size: NSSize(width: 340, height: 96))
        panel.anchorPosition = .topRight
        panel.setContent(
            VolumeView(
                audio: audio,
                onResize: { [weak self] size in self?.panel.updateSize(size) },
                onDismissCancel: { [weak self] in self?.cancelDismiss() },
                onDismissRestore: { [weak self] in self?.scheduleDismiss() }
            )
        )

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
            audio.adjustVolume(by: 1.0 / 16.0)
            showHUD()
        case "down":
            audio.adjustVolume(by: -1.0 / 16.0)
            showHUD()
        case "mute":
            audio.toggleMute()
            showHUD()
        case "show":
            if panel.isVisible {
                panel.dismiss()
            } else {
                panel.updateSize(NSSize(width: 340, height: 460), animate: false)
                panel.setContent(
                    VolumeView(
                        audio: audio,
                        onResize: { [weak self] size in self?.panel.updateSize(size) },
                        onDismissCancel: { [weak self] in self?.cancelDismiss() },
                        onDismissRestore: { [weak self] in self?.scheduleDismiss() }
                    )
                )
                panel.showAt(position: .topRight)
            }
        default:
            break
        }

        let vol = Int(audio.volume * 100)
        let muted = audio.isMuted
        return "{\"volume\":\(vol),\"muted\":\(muted)}"
    }

    func showHUD() {
        if !panel.isVisible {
            // Reset to compact size
            panel.updateSize(NSSize(width: 340, height: 96), animate: false)
            panel.setContent(
                VolumeView(
                    audio: audio,
                    onResize: { [weak self] size in self?.panel.updateSize(size) },
                    onDismissCancel: { [weak self] in self?.cancelDismiss() },
                    onDismissRestore: { [weak self] in self?.scheduleDismiss() }
                )
            )
            panel.showAt(position: .topRight, passive: true)
        }
        // Reset dismiss timer on every volume change
        scheduleDismiss()
    }

    func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.panel.dismiss()
        }
    }

    func cancelDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
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
    fputs("usage: volume-panel daemon|up|down|mute|show\n", stderr)
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
        fputs("volume-panel: daemon not running\n", stderr)
        exit(1)
    }
}
