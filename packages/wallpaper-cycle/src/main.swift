import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let cacheDir = home.appendingPathComponent(".cache/wallpapers")
let processedDir = cacheDir.appendingPathComponent("processed")
let historyFile = cacheDir.appendingPathComponent("history")
let posFile = cacheDir.appendingPathComponent("history_pos")
let stateFile = cacheDir.appendingPathComponent("current")
let lockFile = cacheDir.appendingPathComponent("set_lock")

try? fm.createDirectory(at: processedDir, withIntermediateDirectories: true)

// MARK: - Lock (coordination between next/prev and watch daemon)

func touchLock() {
    fm.createFile(atPath: lockFile.path, contents: nil)
}

func isLocked(seconds: TimeInterval = 10) -> Bool {
    guard let attrs = try? fm.attributesOfItem(atPath: lockFile.path),
          let mod = attrs[.modificationDate] as? Date
    else { return false }
    return Date().timeIntervalSince(mod) < seconds
}

// MARK: - Screen

func screenPixels() -> (w: Int, h: Int, scale: CGFloat) {
    let s = NSScreen.main ?? NSScreen.screens[0]
    let sc = s.backingScaleFactor
    return (Int(s.frame.width * sc), Int(s.frame.height * sc), sc)
}

// MARK: - Find wallpapers

func findStaticWallpapers() -> [URL] {
    let base = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
    guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey])
    else { return [] }
    return en.compactMap { $0 as? URL }.filter { url in
        !url.path.contains(".thumbnails") &&
        ["heic", "jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) &&
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 500_000
    }
}

func findAerialWallpapers() -> [URL] {
    let videosDir = home
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos")
    guard let contents = try? fm.contentsOfDirectory(
        at: videosDir, includingPropertiesForKeys: nil)
    else { return [] }
    return contents.filter { $0.pathExtension.lowercased() == "mov" }
}

func findWallpapers() -> [URL] {
    findStaticWallpapers() + findAerialWallpapers()
}

// MARK: - Extract frame from video

func extractFrame(_ src: URL) -> CGImage? {
    let asset = AVURLAsset(url: src)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = CMTime(seconds: 5, preferredTimescale: 600)
    // Grab a frame ~30% into the video for a representative shot
    var duration = CMTime.zero
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        duration = (try? await asset.load(.duration)) ?? CMTime.zero
        semaphore.signal()
    }
    semaphore.wait()
    guard duration.seconds > 0 else { return nil }
    let target = CMTime(
        seconds: duration.seconds * 0.3,
        preferredTimescale: duration.timescale)
    var result: CGImage?
    let sem2 = DispatchSemaphore(value: 0)
    gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: target)]) { _, image, _, _, _ in
        result = image
        sem2.signal()
    }
    sem2.wait()
    return result
}

// MARK: - Process wallpaper

func process(_ src: URL) -> URL? {
    let px = screenPixels()
    let r = 10.0 * px.scale // macOS window corner radius ≈ 10pt

    // Query yabai for where windows start (bar height + padding).
    // The wallpaper clip rect matches the window area so black corners
    // appear exactly where window rounded corners expose the desktop.
    let windowTopPt: CGFloat = {
        guard let data = runYabai(["query", "--windows"]),
              let wins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return 40.0 }
        return wins.compactMap { w -> CGFloat? in
            guard let frame = w["frame"] as? [String: Any],
                  let y = frame["y"] as? Double,
                  let visible = w["is-visible"] as? Int, visible == 1,
                  let floating = w["is-floating"] as? Int, floating == 0
            else { return nil }
            return CGFloat(y)
        }.min() ?? 40.0
    }()

    let name = src.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "/", with: "_")
    let dest = processedDir.appendingPathComponent("\(px.w)x\(px.h)_\(name).png")
    if fm.fileExists(atPath: dest.path) { return dest }

    let img: CGImage?
    if src.pathExtension.lowercased() == "mov" {
        img = extractFrame(src)
    } else {
        guard let isrc = CGImageSourceCreateWithURL(src as CFURL, nil) else { return nil }
        img = CGImageSourceCreateImageAtIndex(isrc, 0, nil)
    }

    guard let img,
          let ctx = CGContext(
              data: nil, width: px.w, height: px.h,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // Black background
    ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: px.w, height: px.h))

    // Clip to rounded rect matching the window area exactly:
    // - Flush to left/right/bottom edges (no visible border)
    // - Top edge at bar bottom (black above is hidden behind the bar)
    // - Rounded corners at all 4 window corner positions
    // CG origin is bottom-left, Y increases upward.
    let topInsetPx = windowTopPt * px.scale
    let windowRect = CGRect(
        x: 0, y: 0,
        width: CGFloat(px.w),
        height: CGFloat(px.h) - topInsetPx
    )
    ctx.addPath(CGPath(roundedRect: windowRect,
                       cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()

    let (sw, sh) = (CGFloat(img.width), CGFloat(img.height))
    let scale = max(CGFloat(px.w) / sw, CGFloat(px.h) / sh)
    let (dw, dh) = (sw * scale, sh * scale)
    ctx.draw(img, in: CGRect(
        x: (CGFloat(px.w) - dw) / 2,
        y: (CGFloat(px.h) - dh) / 2,
        width: dw, height: dh))

    guard let out = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(
              dest as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dst, out, nil)
    return CGImageDestinationFinalize(dst) ? dest : nil
}

// MARK: - Yabai helper

func runYabai(_ args: [String]) -> Data? {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/run/current-system/sw/bin/yabai")
    p.arguments = ["-m"] + args
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return pipe.fileHandleForReading.readDataToEndOfFile()
}

// MARK: - Set wallpaper (all spaces via yabai)

/// Sets wallpaper for the current space using NSWorkspace (proper macOS API).
func setForCurrentSpace(_ url: URL) {
    guard let screen = NSScreen.main else { return }
    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
        .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue
    ])
}

/// Sets the wallpaper across ALL spaces by switching to each space via yabai
/// and calling NSWorkspace.setDesktopImageURL. This works with WallpaperAgent
/// instead of fighting its plist.
func setWallpaper(_ url: URL) {
    guard let spacesData = runYabai(["query", "--spaces"]),
          let spaces = try? JSONSerialization.jsonObject(with: spacesData) as? [[String: Any]]
    else {
        // Fallback: just set current space
        setForCurrentSpace(url)
        return
    }

    let currentIndex = spaces.first(where: {
        ($0["has-focus"] as? Int) == 1
    })?["index"] as? Int ?? 1

    // Set current space first
    setForCurrentSpace(url)

    // Visit each other space and set
    for space in spaces {
        guard let idx = space["index"] as? Int, idx != currentIndex else { continue }
        _ = runYabai(["space", "--focus", "\(idx)"])
        Thread.sleep(forTimeInterval: 0.15)
        setForCurrentSpace(url)
    }

    // Return to original space
    _ = runYabai(["space", "--focus", "\(currentIndex)"])
}

// MARK: - Get current wallpaper

func currentWallpaperURL() -> URL? {
    guard let screen = NSScreen.main else { return nil }
    return NSWorkspace.shared.desktopImageURL(for: screen)
}

// MARK: - History

func lines(_ u: URL) -> [String] {
    (try? String(contentsOf: u, encoding: .utf8))?
        .split(separator: "\n").map(String.init) ?? []
}

func pos() -> Int {
    Int((try? String(contentsOf: posFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "-1") ?? -1
}

func setPos(_ p: Int) {
    try? "\(p)".write(to: posFile, atomically: true, encoding: .utf8)
}

func save(_ p: String) {
    try? p.write(to: stateFile, atomically: true, encoding: .utf8)
}

func push(_ path: String) {
    var h = lines(historyFile)
    let p = pos()
    if p >= 0, p < h.count - 1 { h = Array(h.prefix(p + 1)) }
    h.append(path)
    if h.count > 50 { h = Array(h.suffix(50)) }
    try? (h.joined(separator: "\n") + "\n")
        .write(to: historyFile, atomically: true, encoding: .utf8)
    setPos(h.count - 1)
}

// MARK: - Commands

func next() {
    touchLock()

    let h = lines(historyFile)
    let p = pos()

    if p >= 0, p < h.count - 1 {
        setPos(p + 1); save(h[p + 1])
        setWallpaper(URL(fileURLWithPath: h[p + 1]))
        return
    }

    let all = findWallpapers()
    guard !all.isEmpty else {
        fputs("no wallpapers found\n", stderr); exit(1)
    }

    for _ in 0..<3 {
        if let d = process(all.randomElement()!) {
            push(d.path); save(d.path); setWallpaper(d)
            return
        }
    }
    fputs("failed to process wallpaper\n", stderr); exit(1)
}

func prev() {
    touchLock()

    let h = lines(historyFile)
    let p = pos()
    guard p > 0 else {
        fputs("no previous wallpaper\n", stderr); exit(1)
    }
    setPos(p - 1); save(h[p - 1])
    setWallpaper(URL(fileURLWithPath: h[p - 1]))
}

func current() {
    guard let p = try? String(contentsOf: stateFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty
    else { fputs("no wallpaper set\n", stderr); exit(1) }
    print(p)
}

/// Daemon: polls for wallpaper changes, auto-processes any new wallpaper
/// that wasn't already processed. Respects the lock file to avoid fighting
/// with manual next/prev commands.
func watch() {
    var lastDetected: URL? = nil

    // Process current wallpaper immediately on start
    if let cur = currentWallpaperURL() {
        if !cur.path.hasPrefix(processedDir.path) {
            touchLock()
            if let processed = process(cur) {
                setWallpaper(processed)
                lastDetected = processed
            }
        } else {
            lastDetected = cur
        }
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 3, repeating: 3.0)
    timer.setEventHandler {
        if isLocked() { return }

        guard let cur = currentWallpaperURL() else { return }
        if cur == lastDetected { return }
        lastDetected = cur

        if cur.path.hasPrefix(processedDir.path) { return }

        touchLock()
        if let processed = process(cur) {
            setWallpaper(processed)
            lastDetected = processed
        }
    }
    timer.resume()
    dispatchMain()
}

// MARK: - Main

NSApplication.shared.setActivationPolicy(.prohibited)

switch CommandLine.arguments.dropFirst().first ?? "next" {
case "next": next()
case "prev": prev()
case "current": current()
case "watch": watch()
default:
    fputs("usage: wallpaper-cycle [next|prev|current|watch]\n", stderr)
    exit(1)
}
