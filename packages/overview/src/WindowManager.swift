import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let space: Int
    let frame: CGRect
    let image: NSImage?
    let icon: NSImage
}

struct SpaceInfo: Identifiable {
    let id: Int
    let index: Int
    let hasFocus: Bool
    let windowIDs: [Int]
}

private struct YabaiWindow: Decodable {
    let id: Int, pid: Int, app: String, title: String, space: Int
    let frame: YF
    let isVisible: Bool, isHidden: Bool, isMinimized: Bool, scratchpad: String
    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, space, frame, scratchpad
        case isVisible = "is-visible", isHidden = "is-hidden", isMinimized = "is-minimized"
    }
}
private struct YF: Decodable { let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat }
private struct YabaiSpace: Decodable {
    let id: Int, index: Int, hasFocus: Bool, windows: [Int]
    enum CodingKeys: String, CodingKey { case id, index, windows; case hasFocus = "has-focus" }
}

enum WindowManager {

    static func querySpaces() -> [SpaceInfo] {
        guard let s: [YabaiSpace] = queryYabai(["--spaces"]) else { return [] }
        return s.map { SpaceInfo(id: $0.id, index: $0.index, hasFocus: $0.hasFocus, windowIDs: $0.windows) }
            .sorted { $0.index < $1.index }
    }

    /// Synchronous metadata-only query (no screenshots). Instant.
    static func queryWindowInfo() -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        return yabai
            .filter { !$0.isHidden && !$0.isMinimized && $0.app != "overview" && $0.app != "sketchybar" && $0.scratchpad.isEmpty }
            .map { win in
                let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)
                let icon: NSImage
                if let r = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                    icon = r.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                } else { icon = NSWorkspace.shared.icon(for: .applicationBundle) }
                return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                                  space: win.space, frame: frame, image: nil, icon: icon)
            }
    }

    /// Fast capture: display composite + crop. Captures windows WITH their blur/vibrancy intact.
    /// MUST be called from a background thread (uses semaphore for SCK).
    static func captureFromComposite() -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        let valid = yabai.filter { !$0.isHidden && !$0.isMinimized && $0.app != "overview" && $0.app != "sketchybar" && $0.scratchpad.isEmpty }
        guard !valid.isEmpty else { return [] }

        // Single display composite capture (fast ~100ms)
        var composite: CGImage?
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
               let display = content.displays.first {
                let f = SCContentFilter(display: display, excludingWindows: [])
                let c = SCStreamConfiguration()
                c.width = display.width * 2; c.height = display.height * 2; c.showsCursor = false
                composite = try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c)
            }
            sem.signal()
        }
        sem.wait()

        let scale: CGFloat
        if let c = composite, let s = NSScreen.main { scale = CGFloat(c.width) / s.frame.width }
        else { scale = 2.0 }

        return valid.map { win in
            let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)
            var img: NSImage? = nil
            if win.isVisible, let c = composite {
                let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                                  width: frame.width * scale, height: frame.height * scale)
                if let cropped = c.cropping(to: crop) {
                    img = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
                }
            }
            let icon: NSImage
            if let r = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                icon = r.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            } else { icon = NSWorkspace.shared.icon(for: .applicationBundle) }
            return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                              space: win.space, frame: frame, image: img, icon: icon)
        }
    }

    /// Slow async per-window capture — gets screenshots for ALL windows including off-screen.
    static func captureAllWindowsAsync() async -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        let valid = yabai.filter { !$0.isHidden && !$0.isMinimized && $0.app != "overview" && $0.app != "sketchybar" && $0.scratchpad.isEmpty }
        guard !valid.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [] }
        let scMap = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

        return await withTaskGroup(of: WindowInfo?.self, returning: [WindowInfo].self) { group in
            for win in valid {
                group.addTask {
                    let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)
                    var img: NSImage? = nil
                    if let scw = scMap[CGWindowID(win.id)] {
                        let f = SCContentFilter(desktopIndependentWindow: scw)
                        let c = SCStreamConfiguration()
                        c.width = Int(win.frame.w) * 2; c.height = Int(win.frame.h) * 2; c.showsCursor = false
                        if let cg = try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c) {
                            img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }
                    }
                    let icon: NSImage
                    if let r = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                        icon = r.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                    } else { icon = NSWorkspace.shared.icon(for: .applicationBundle) }
                    return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                                      space: win.space, frame: frame, image: img, icon: icon)
                }
            }
            var results: [WindowInfo] = []
            for await info in group { if let info { results.append(info) } }
            return results
        }
    }

    /// Load the desktop wallpaper image file.
    static func loadWallpaper() -> NSImage? {
        // NSWorkspace returns the actual current wallpaper path
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           url.path != "/System/Library/CoreServices/DefaultDesktop.heic",
           let img = NSImage(contentsOf: url) {
            return img
        }
        // Fallback: wallpaper-cycle state file
        let stateFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/wallpapers/current")
        guard let path = try? String(contentsOf: stateFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// Blur a CGImage using CIFilter (for wallpaper backdrop behind transparent windows).
    static func blurImage(_ image: CGImage, radius: CGFloat = 40) -> CGImage? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let ctx = CIContext()
        // CIGaussianBlur extends the image bounds — crop back to original
        return ctx.createCGImage(output, from: ci.extent)
    }

    /// Composite a window screenshot (with alpha) onto a blurred wallpaper crop.
    /// Produces an opaque image that looks like the window with wallpaper blur showing through.
    static func compositeWindow(screenshot: NSImage, blurredWP: CGImage, frame: CGRect, screenSize: CGSize) -> NSImage {
        let scale = CGFloat(blurredWP.width) / screenSize.width
        let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                          width: frame.width * scale, height: frame.height * scale)
        guard let wpCrop = blurredWP.cropping(to: crop) else { return screenshot }

        let w = Int(frame.width * 2), h = Int(frame.height * 2)  // retina
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return screenshot }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // Draw blurred wallpaper as background
        ctx.draw(wpCrop, in: rect)
        // Draw window screenshot on top (alpha composites naturally)
        if let screenshotCG = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(screenshotCG, in: rect)
        }
        guard let result = ctx.makeImage() else { return screenshot }
        return NSImage(cgImage: result, size: NSSize(width: w, height: h))
    }

    // MARK: - Actions

    static func focusWindow(_ id: Int) { run(["yabai", "-m", "window", "\(id)", "--focus"]) }
    static func focusSpace(_ idx: Int) { run(["yabai", "-m", "space", "--focus", "\(idx)"]) }
    static func moveWindow(_ id: Int, toSpace s: Int) { run(["yabai", "-m", "window", "\(id)", "--space", "\(s)"]) }
    static func reorderSpace(_ from: Int, to: Int) { run(["yabai", "-m", "space", "\(from)", "--move", "\(to)"]) }

    // MARK: - Private

    private static func queryYabai<T: Decodable>(_ args: [String]) -> T? {
        let p = Pipe(), t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        t.arguments = ["yabai", "-m", "query"] + args
        t.standardOutput = p; t.standardError = FileHandle.nullDevice
        do { try t.run() } catch { return nil }
        // Read before waitUntilExit to avoid pipe buffer deadlock
        let data = p.fileHandleForReading.readDataToEndOfFile()
        t.waitUntilExit()
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private static func run(_ args: [String]) -> Int32 {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        t.arguments = args
        t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
        do { try t.run() } catch { return -1 }
        t.waitUntilExit()
        return t.terminationStatus
    }
}
