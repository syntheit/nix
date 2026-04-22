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

// MARK: - Yabai JSON schemas

private struct YabaiWindow: Decodable {
    let id: Int
    let pid: Int
    let app: String
    let title: String
    let space: Int
    let frame: YabaiFrame
    let isVisible: Bool
    let isHidden: Bool
    let isMinimized: Bool
    let scratchpad: String

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, space, frame, scratchpad
        case isVisible   = "is-visible"
        case isHidden    = "is-hidden"
        case isMinimized = "is-minimized"
    }
}

private struct YabaiFrame: Decodable {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
}

private struct YabaiSpace: Decodable {
    let id: Int
    let index: Int
    let hasFocus: Bool
    let windows: [Int]
    enum CodingKeys: String, CodingKey {
        case id, index, windows
        case hasFocus = "has-focus"
    }
}

enum WindowManager {

    // MARK: - Queries

    static func querySpaces() -> [SpaceInfo] {
        guard let spaces: [YabaiSpace] = queryYabai(["--spaces"]) else { return [] }
        return spaces.map { SpaceInfo(id: $0.id, index: $0.index, hasFocus: $0.hasFocus, windowIDs: $0.windows) }
            .sorted { $0.index < $1.index }
    }

    /// Capture all windows across all spaces using per-window ScreenCaptureKit capture.
    static func captureAllWindows() async -> [WindowInfo] {
        guard let yabaiWindows: [YabaiWindow] = queryYabai(["--windows"]) else { return [] }

        let valid = yabaiWindows.filter {
            !$0.isHidden && !$0.isMinimized && $0.app != "overview" && $0.scratchpad.isEmpty
        }
        guard !valid.isEmpty else { return [] }

        // Get ScreenCaptureKit window list for per-window capture
        let scWindows: [CGWindowID: SCWindow]
        if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
            scWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        } else {
            scWindows = [:]
        }

        // Capture all windows concurrently
        return await withTaskGroup(of: WindowInfo?.self, returning: [WindowInfo].self) { group in
            for win in valid {
                group.addTask {
                    let frame = CGRect(x: win.frame.x, y: win.frame.y, width: win.frame.w, height: win.frame.h)

                    // Per-window capture via ScreenCaptureKit (works for off-screen windows too)
                    var nsImage: NSImage? = nil
                    if let scWindow = scWindows[CGWindowID(win.id)] {
                        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                        let config = SCStreamConfiguration()
                        // Capture at 2x (Retina) for sharp previews
                        config.width = Int(win.frame.w) * 2
                        config.height = Int(win.frame.h) * 2
                        config.showsCursor = false
                        if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                            nsImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        }
                    }

                    let icon: NSImage
                    if let running = NSRunningApplication(processIdentifier: pid_t(win.pid)) {
                        icon = running.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
                    } else {
                        icon = NSWorkspace.shared.icon(for: .applicationBundle)
                    }

                    return WindowInfo(id: win.id, pid: win.pid, app: win.app, title: win.title,
                                      space: win.space, frame: frame, image: nsImage, icon: icon)
                }
            }

            var results: [WindowInfo] = []
            for await info in group {
                if let info { results.append(info) }
            }
            return results
        }
    }

    // MARK: - Actions

    static func focusWindow(_ windowID: Int) {
        run(["yabai", "-m", "window", "\(windowID)", "--focus"])
    }

    static func focusSpace(_ spaceIndex: Int) {
        run(["yabai", "-m", "space", "--focus", "\(spaceIndex)"])
    }

    static func moveWindow(_ windowID: Int, toSpace spaceIndex: Int) {
        run(["yabai", "-m", "window", "\(windowID)", "--space", "\(spaceIndex)"])
    }

    static func reorderSpace(_ fromIndex: Int, to targetIndex: Int) {
        // yabai --swap swaps two spaces by index
        run(["yabai", "-m", "space", "\(fromIndex)", "--swap", "\(targetIndex)"])
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
