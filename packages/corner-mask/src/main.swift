import AppKit

let kR: CGFloat = 11  // slightly > macOS ~10pt window corner radius for margin

let excludedApps: Set<String> = [
    // Apps that already handle corners well (dark backgrounds, etc.)
]

// MARK: - Window query

struct WinRect: Equatable {
    let x, y, w, h: CGFloat
}

func queryWindows() -> [WinRect] {
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
        guard let f = w["frame"] as? [String: Any],
              let x = f["x"] as? Double, let y = f["y"] as? Double,
              let ww = f["w"] as? Double, let hh = f["h"] as? Double,
              let app = w["app"] as? String,
              let floating = w["is-floating"] as? Int, floating == 0,
              let minimized = w["is-minimized"] as? Int, minimized == 0,
              !excludedApps.contains(app)
        else { return nil }
        return WinRect(x: CGFloat(x), y: CGFloat(y), w: CGFloat(ww), h: CGFloat(hh))
    }
}

// MARK: - Corner drawing

class CornerView: NSView {
    var windows: [WinRect] = []

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let screenH = bounds.height
        let r = kR

        ctx.setFillColor(NSColor.black.cgColor)

        for win in windows {
            let left = win.x
            let right = win.x + win.w
            let top = screenH - win.y
            let bottom = screenH - (win.y + win.h)

            // Each corner: R×R square + quarter-circle pie, even-odd filled.
            // Result = only the ear (gap between square corner and arc) is filled.

            // Top-left
            var cp = CGMutablePath()
            cp.addRect(CGRect(x: left, y: top - r, width: r, height: r))
            cp.move(to: CGPoint(x: left + r, y: top - r))
            cp.addArc(center: CGPoint(x: left + r, y: top - r), radius: r,
                      startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            cp.closeSubpath()
            ctx.addPath(cp); ctx.fillPath(using: .evenOdd)

            // Top-right
            cp = CGMutablePath()
            cp.addRect(CGRect(x: right - r, y: top - r, width: r, height: r))
            cp.move(to: CGPoint(x: right - r, y: top - r))
            cp.addArc(center: CGPoint(x: right - r, y: top - r), radius: r,
                      startAngle: .pi / 2, endAngle: 0, clockwise: true)
            cp.closeSubpath()
            ctx.addPath(cp); ctx.fillPath(using: .evenOdd)

            // Bottom-left
            cp = CGMutablePath()
            cp.addRect(CGRect(x: left, y: bottom, width: r, height: r))
            cp.move(to: CGPoint(x: left + r, y: bottom + r))
            cp.addArc(center: CGPoint(x: left + r, y: bottom + r), radius: r,
                      startAngle: .pi, endAngle: -.pi / 2, clockwise: false)
            cp.closeSubpath()
            ctx.addPath(cp); ctx.fillPath(using: .evenOdd)

            // Bottom-right
            cp = CGMutablePath()
            cp.addRect(CGRect(x: right - r, y: bottom, width: r, height: r))
            cp.move(to: CGPoint(x: right - r, y: bottom + r))
            cp.addArc(center: CGPoint(x: right - r, y: bottom + r), radius: r,
                      startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            cp.closeSubpath()
            ctx.addPath(cp); ctx.fillPath(using: .evenOdd)
        }
    }
}

// MARK: - Overlay window

class OverlayWindow: NSWindow {
    let cornerView: CornerView

    init(screen: NSScreen) {
        cornerView = CornerView(frame: screen.frame)
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.hasShadow = false
    }

    func refresh() {
        let newWindows = queryWindows()
        if newWindows != cornerView.windows {
            cornerView.windows = newWindows
            cornerView.needsDisplay = true
        }
    }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlay: OverlayWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { return }
        overlay = OverlayWindow(screen: screen)
        overlay.orderFrontRegardless()
        overlay.refresh()

        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.overlay.refresh()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.overlay.refresh()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
