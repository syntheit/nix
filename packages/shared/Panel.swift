import AppKit
import SwiftUI

// MARK: - Floating Panel

class SystemPanel: NSPanel {
    private var clickMonitor: Any?
    private var escapeMonitor: Any?

    init(size: NSSize = NSSize(width: 320, height: 200)) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContent<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: AnyView(view.ignoresSafeArea()))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        contentView = hosting
    }

    func showCentered() {
        showAt(position: .center)
    }

    func showAt(position: PanelPosition) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let origin: NSPoint

        switch position {
        case .center:
            origin = NSPoint(x: sf.midX - frame.width / 2, y: sf.midY - frame.height / 2)
        case .topRight:
            origin = NSPoint(x: sf.maxX - frame.width - 16, y: sf.maxY - frame.height - 16)
        case .topCenter:
            origin = NSPoint(x: sf.midX - frame.width / 2, y: sf.maxY - frame.height - 16)
        }

        setFrameOrigin(origin)
        alphaValue = 0
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }

        installMonitors()
    }

    enum PanelPosition {
        case center, topRight, topCenter
    }

    func dismiss() {
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    var anchorPosition: PanelPosition = .center

    func updateSize(_ size: NSSize, animate: Bool = true) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let newOrigin: NSPoint
        switch anchorPosition {
        case .center:
            newOrigin = NSPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)
        case .topRight:
            newOrigin = NSPoint(x: sf.maxX - size.width - 16, y: sf.maxY - size.height - 16)
        case .topCenter:
            newOrigin = NSPoint(x: sf.midX - size.width / 2, y: sf.maxY - size.height - 16)
        }
        let newFrame = NSRect(origin: newOrigin, size: size)

        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    private func installMonitors() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
    }
}

// MARK: - IPC Server

class IPCServer {
    let socketPath: String
    var handler: ((String) -> String)?

    init(path: String) {
        socketPath = path

        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    func start() {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                _ = memcpy(ptr, cstr, min(maxLen, socketPath.utf8.count))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { a in
                bind(fd, a, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(fd); return }
        listen(fd, 5)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFD = accept(fd, nil, nil)
                guard clientFD >= 0, let self = self else { continue }

                var buffer = [UInt8](repeating: 0, count: 1024)
                let n = read(clientFD, &buffer, buffer.count - 1)
                guard n > 0 else { close(clientFD); continue }

                let cmd = String(bytes: buffer[0..<n], encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let response = DispatchQueue.main.sync { self.handler?(cmd) ?? "ok" }

                let data = (response + "\n").data(using: .utf8)!
                data.withUnsafeBytes { ptr in
                    _ = write(clientFD, ptr.baseAddress!, data.count)
                }
                close(clientFD)
            }
        }
    }
}

// MARK: - IPC Client

func sendIPC(_ message: String, socketPath: String) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    socketPath.withCString { cstr in
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            _ = memcpy(ptr, cstr, min(maxLen, socketPath.utf8.count))
        }
    }

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { a in
            connect(fd, a, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else { return nil }

    let data = (message + "\n").data(using: .utf8)!
    data.withUnsafeBytes { ptr in
        _ = write(fd, ptr.baseAddress!, data.count)
    }

    var buffer = [UInt8](repeating: 0, count: 4096)
    let n = read(fd, &buffer, buffer.count - 1)
    guard n > 0 else { return nil }
    return String(bytes: buffer[0..<n], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Accent Colors

enum Accent {
    static let blue = Color(red: 0.48, green: 0.73, blue: 1.0)      // #7aa2f7
    static let green = Color(red: 0.45, green: 0.85, blue: 0.56)    // #73daca
    static let red = Color(red: 0.96, green: 0.51, blue: 0.53)      // #f7768e
    static let yellow = Color(red: 0.88, green: 0.77, blue: 0.42)   // #e0af68
    static let subtext = Color(red: 0.45, green: 0.48, blue: 0.58)  // #737aa2
}
