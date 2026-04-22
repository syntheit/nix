import AppKit
import SwiftUI

// Apps that already handle their own corners well (dark backgrounds, etc.)
let excludedApps: Set<String> = [
    "Ghostty",
]

let kCornerRadius: CGFloat = 10

// MARK: - Yabai query

struct WinFrame {
    let x, y, w, h: CGFloat
    let app: String
}

func getVisibleWindows() -> [WinFrame] {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/run/current-system/sw/bin/yabai")
    p.arguments = ["-m", "query", "--windows", "--space"]
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let wins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }

    return wins.compactMap { w in
        guard let frame = w["frame"] as? [String: Any],
              let x = frame["x"] as? Double,
              let y = frame["y"] as? Double,
              let width = frame["w"] as? Double,
              let height = frame["h"] as? Double,
              let app = w["app"] as? String,
              let floating = w["is-floating"] as? Int, floating == 0,
              let minimized = w["is-minimized"] as? Int, minimized == 0
        else { return nil }
        if excludedApps.contains(app) { return nil }
        return WinFrame(x: CGFloat(x), y: CGFloat(y),
                        w: CGFloat(width), h: CGFloat(height), app: app)
    }
}

// MARK: - Corner drawing

struct CornerCanvas: View {
    let windows: [WinFrame]

    var body: some View {
        Canvas { ctx, size in
            for win in windows {
                drawCorners(ctx: ctx, win: win)
            }
        }
        .allowsHitTesting(false)
    }

    func drawCorners(ctx: GraphicsContext, win: WinFrame) {
        let r = kCornerRadius
        // Top-left
        var p = Path()
        p.move(to: CGPoint(x: win.x, y: win.y))
        p.addLine(to: CGPoint(x: win.x + r, y: win.y))
        p.addArc(center: CGPoint(x: win.x + r, y: win.y + r),
                 radius: r, startAngle: .degrees(-90),
                 endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: win.x, y: win.y))
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))

        // Top-right
        p = Path()
        p.move(to: CGPoint(x: win.x + win.w, y: win.y))
        p.addLine(to: CGPoint(x: win.x + win.w - r, y: win.y))
        p.addArc(center: CGPoint(x: win.x + win.w - r, y: win.y + r),
                 radius: r, startAngle: .degrees(-90),
                 endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: win.x + win.w, y: win.y))
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))

        // Bottom-left
        p = Path()
        p.move(to: CGPoint(x: win.x, y: win.y + win.h))
        p.addLine(to: CGPoint(x: win.x + r, y: win.y + win.h))
        p.addArc(center: CGPoint(x: win.x + r, y: win.y + win.h - r),
                 radius: r, startAngle: .degrees(90),
                 endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: win.x, y: win.y + win.h))
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))

        // Bottom-right
        p = Path()
        p.move(to: CGPoint(x: win.x + win.w, y: win.y + win.h))
        p.addLine(to: CGPoint(x: win.x + win.w - r, y: win.y + win.h))
        p.addArc(center: CGPoint(x: win.x + win.w - r, y: win.y + win.h - r),
                 radius: r, startAngle: .degrees(90),
                 endAngle: .degrees(0), clockwise: true)
        p.addLine(to: CGPoint(x: win.x + win.w, y: win.y + win.h))
        p.closeSubpath()
        ctx.fill(p, with: .color(.black))
    }
}

// MARK: - Overlay window

class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        self.level = NSWindow.Level(rawValue: 1) // just above normal windows
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.hasShadow = false
        self.title = "corner-mask"
    }

    func refresh() {
        let windows = getVisibleWindows()
        let view = CornerCanvas(windows: windows)
        self.contentView = NSHostingView(rootView: view)
    }
}

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlay: OverlayWindow!
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main else { return }
        overlay = OverlayWindow(screen: screen)
        overlay.orderFrontRegardless()
        overlay.refresh()

        // Poll for window changes
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.overlay.refresh()
        }

        // Also refresh on space change
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.overlay.refresh()
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
