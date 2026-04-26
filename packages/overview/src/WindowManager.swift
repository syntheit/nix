import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    var space: Int
    let frame: CGRect
    var image: NSImage?
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

    /// Synchronous metadata-only query (no screenshots).
    static func queryWindowInfo() -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        return validWindows(yabai).map { win in
            let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)
            return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                              space: win.space, frame: frame, image: nil, icon: appIcon(for: win.pid))
        }
    }

    /// Fast capture: display composite + crop. Captures windows WITH their blur/vibrancy intact.
    /// Also saves the full composite into the cache for the currently focused space.
    static func captureFromComposite() async -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        let valid = validWindows(yabai)
        guard !valid.isEmpty else { return [] }

        // Single display composite capture (~100ms)
        var composite: CGImage?
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
           let display = content.displays.first {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let exclude = content.windows.filter { $0.owningApplication?.processID == myPID }
            let f = SCContentFilter(display: display, excludingWindows: exclude)
            let c = SCStreamConfiguration()
            c.width = display.width * 2; c.height = display.height * 2; c.showsCursor = false
            composite = try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c)
        }

        // Save composite to cache for the current focused space
        if let composite,
           let spaces: [YabaiSpace] = queryYabai(["--spaces"]),
           let focused = spaces.first(where: { $0.hasFocus }) {
            compositeCache[focused.index] = composite
        }

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
            return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                              space: win.space, frame: frame, image: img, icon: appIcon(for: win.pid))
        }
    }

    /// Async per-window capture — gets screenshots for ALL windows including off-screen.
    static func captureAllWindowsAsync() async -> [WindowInfo] {
        guard let yabai: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }
        let valid = validWindows(yabai)
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
                    return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                                      space: win.space, frame: frame, image: img, icon: appIcon(for: win.pid))
                }
            }
            var results: [WindowInfo] = []
            for await info in group { if let info { results.append(info) } }
            return results
        }
    }

    /// Load the desktop wallpaper image file.
    static func loadWallpaper() -> NSImage? {
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           url.path != "/System/Library/CoreServices/DefaultDesktop.heic",
           let img = NSImage(contentsOf: url) {
            return img
        }
        let stateFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/wallpapers/current")
        guard let path = try? String(contentsOf: stateFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    // MARK: - Composite cache for workspace switching

    static var compositeCache: [Int: CGImage] = [:]

    /// Capture the full display composite as a raw CGImage (with blur/vibrancy).
    static func captureDisplayComposite() async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let exclude = content.windows.filter { $0.owningApplication?.processID == myPID }
        let f = SCContentFilter(display: display, excludingWindows: exclude)
        let c = SCStreamConfiguration()
        c.width = display.width * 2; c.height = display.height * 2; c.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: f, configuration: c)
    }

    /// Capture and cache the composite for the currently focused space.
    static func cacheCurrentSpace() async {
        guard let spaces: [YabaiSpace] = queryYabai(["--spaces"]),
              let focused = spaces.first(where: { $0.hasFocus }) else { return }
        if let img = await captureDisplayComposite() {
            compositeCache[focused.index] = img
        }
    }

    /// Populate the composite cache by visiting each occupied space.
    /// Call behind an opaque overlay so the user doesn't see rapid switching.
    static func populateCache() async {
        let spaces = querySpaces()
        let occupied = spaces.filter { !$0.windowIDs.isEmpty }
        guard let focused = spaces.first(where: { $0.hasFocus }) else { return }
        let originalIndex = focused.index

        // Cache the current space first (no switch needed)
        if let img = await captureDisplayComposite() {
            compositeCache[originalIndex] = img
        }

        // Visit each other occupied space
        for space in occupied where space.index != originalIndex {
            focusSpace(space.index)
            // Brief wait for WindowServer to composite the new space
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if let img = await captureDisplayComposite() {
                compositeCache[space.index] = img
            }
        }

        // Return to original space
        if occupied.count > 1 || occupied.first?.index != originalIndex {
            focusSpace(originalIndex)
        }
        print("[overview] composite cache populated: \(compositeCache.count) spaces")
    }

    /// Invalidate the entire composite cache (e.g., on screen resolution change).
    static func invalidateCache() {
        compositeCache.removeAll()
    }

    // MARK: - Async run (non-blocking, for sketchybar updates during gestures)

    static func runAsync(_ args: [String]) {
        DispatchQueue.global(qos: .userInteractive).async {
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            t.arguments = args
            t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
            do { try t.run() } catch { return }
            t.waitUntilExit()
        }
    }

    // MARK: - Actions

    static func focusWindow(_ id: Int) { run(["yabai", "-m", "window", "\(id)", "--focus"]) }
    static func focusSpace(_ idx: Int) { run(["yabai", "-m", "space", "--focus", "\(idx)"]) }
    static func moveWindow(_ id: Int, toSpace s: Int) { run(["yabai", "-m", "window", "\(id)", "--space", "\(s)"]) }
    static func reorderSpace(_ from: Int, to: Int) { run(["yabai", "-m", "space", "\(from)", "--move", "\(to)"]) }

    // MARK: - Private

    private static func validWindows(_ yabai: [YabaiWindow]) -> [YabaiWindow] {
        yabai.filter { !$0.isHidden && !$0.isMinimized
            && $0.app.lowercased() != "overview" && $0.app.lowercased() != "sketchybar"
            && $0.scratchpad.isEmpty }
    }

    private static func appIcon(for pid: Int) -> NSImage {
        if let r = NSRunningApplication(processIdentifier: pid_t(pid)) {
            return r.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private static func queryYabai<T: Decodable>(_ args: [String]) -> T? {
        let p = Pipe(), t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        t.arguments = ["yabai", "-m", "query"] + args
        t.standardOutput = p; t.standardError = FileHandle.nullDevice
        do { try t.run() } catch { return nil }
        let data = p.fileHandleForReading.readDataToEndOfFile()
        t.waitUntilExit()
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    static func run(_ args: [String]) -> Int32 {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        t.arguments = args
        t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
        do { try t.run() } catch { return -1 }
        t.waitUntilExit()
        return t.terminationStatus
    }
}
