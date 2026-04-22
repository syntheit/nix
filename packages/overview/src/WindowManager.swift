import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let frame: CGRect
    let image: NSImage?
    let icon: NSImage
}

private struct YabaiWindow: Decodable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let frame: YabaiFrame
    let isVisible: Bool
    let isHidden: Bool
    let isMinimized: Bool
    let scratchpad: String

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, frame, scratchpad
        case isVisible   = "is-visible"
        case isHidden    = "is-hidden"
        case isMinimized = "is-minimized"
    }
}

private struct YabaiFrame: Decodable {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
}

enum WindowManager {

    /// Capture visible windows on the current yabai space using ScreenCaptureKit
    /// display capture + per-window crop.
    static func captureWindows() async -> [WindowInfo] {
        guard let yabaiWindows: [YabaiWindow] = queryYabai(["--windows", "--space"]) else { return [] }

        let visible = yabaiWindows.filter {
            $0.isVisible && !$0.isHidden && !$0.isMinimized && $0.app != "overview"
        }
        guard !visible.isEmpty else { return [] }

        // Capture full display via ScreenCaptureKit
        let composite = await captureDisplay()
        let scale: CGFloat
        if let composite, let screen = NSScreen.main {
            scale = CGFloat(composite.width) / screen.frame.width
        } else {
            scale = 2.0
        }

        return visible.compactMap { win in
            var nsImage: NSImage? = nil
            if let composite {
                let crop = CGRect(
                    x: win.frame.x * scale,
                    y: win.frame.y * scale,
                    width: win.frame.w * scale,
                    height: win.frame.h * scale
                )
                if let cropped = composite.cropping(to: crop) {
                    nsImage = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
                }
            }

            let icon: NSImage
            if let running = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                icon = running.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            } else {
                icon = NSWorkspace.shared.icon(for: .applicationBundle)
            }

            let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)
            return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title, frame: frame, image: nsImage, icon: icon)
        }
        // Sort by spatial position: left-to-right, top-to-bottom
        .sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) < 50 {
                return a.frame.minX < b.frame.minX
            }
            return a.frame.minY < b.frame.minY
        }
    }

    /// Capture the full display as a CGImage.
    private static func captureDisplay() async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first else { return nil }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width * 2  // Retina
        config.height = display.height * 2
        config.showsCursor = false

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func focusWindow(_ windowID: Int) {
        run(["yabai", "-m", "window", "\(windowID)", "--focus"])
    }

    // MARK: - Helpers

    private static func queryYabai<T: Decodable>(_ args: [String]) -> T? {
        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["yabai", "-m", "query"] + args
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        return try? JSONDecoder().decode(T.self, from: pipe.fileHandleForReading.readDataToEndOfFile())
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
