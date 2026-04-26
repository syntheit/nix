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
let queueFile = cacheDir.appendingPathComponent("queue")

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

@discardableResult
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

// MARK: - Set wallpaper
//
// `NSWorkspace.setDesktopImageURL` always targets the *currently visible*
// Space on the given screen — macOS has no public API for an arbitrary Space.
// Two modes:
//
//   • allSpaces = false  →  set wallpaper on the visible Space only. Cheap,
//                            no flicker. Used by the watch daemon, which fires
//                            on every space switch and must NOT yank the user
//                            around.
//   • allSpaces = true   →  walk every yabai Space, apply, return to original.
//                            Visible space-switch flicker. Used by `next` and
//                            `prev` only.

func applyToVisibleSpace(_ url: URL) {
    let opts: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue
    ]
    for screen in NSScreen.screens {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: opts)
    }
}

func setWallpaper(_ url: URL, allSpaces: Bool = true) {
    if !allSpaces {
        applyToVisibleSpace(url)
        return
    }

    guard let data = runYabai(["query", "--spaces"]),
          let spaces = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          !spaces.isEmpty
    else {
        applyToVisibleSpace(url)
        return
    }

    let originalIndex = spaces.first { ($0["has-focus"] as? Int) == 1 }?["index"] as? Int
    let indices = spaces.compactMap { $0["index"] as? Int }.sorted()

    for idx in indices {
        runYabai(["space", "--focus", "\(idx)"])
        Thread.sleep(forTimeInterval: 0.18)  // wait for Space switch to settle
        applyToVisibleSpace(url)
    }

    if let original = originalIndex, indices.last != original {
        runYabai(["space", "--focus", "\(original)"])
    }
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

/// Refill the persistent queue with every available wallpaper in random order.
/// Returns the new queue. The queue file persists across invocations so that
/// each wallpaper is shown exactly once before any repeats.
func refillQueue() -> [String] {
    let shuffled = findWallpapers().shuffled().map { $0.path }
    try? (shuffled.joined(separator: "\n") + "\n")
        .write(to: queueFile, atomically: true, encoding: .utf8)
    return shuffled
}

func next() {
    touchLock()

    let currentPath = (try? String(contentsOf: stateFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Try up to 10 times in case process() fails for a particular source.
    for _ in 0..<10 {
        var queue = lines(queueFile)
        if queue.isEmpty { queue = refillQueue() }
        guard !queue.isEmpty else {
            fputs("no wallpapers found\n", stderr); exit(1)
        }
        let candidate = queue.removeFirst()
        try? (queue.joined(separator: "\n") + "\n")
            .write(to: queueFile, atomically: true, encoding: .utf8)

        let url = URL(fileURLWithPath: candidate)
        guard let processed = process(url) else { continue }
        // Skip the current wallpaper if it happens to be next in the queue.
        if processed.path == currentPath { continue }
        push(processed.path); save(processed.path); setWallpaper(processed)
        return
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

    // The watch daemon runs forever and fires on every Space switch (because
    // each Space has its own desktop image, so currentWallpaperURL changes).
    // It must NEVER iterate Spaces — that would make the user unable to stay
    // on a Space whose wallpaper isn't yet processed (the iterate yanks them
    // back to the original Space). Use allSpaces:false to apply only to the
    // currently visible Space.

    if let cur = currentWallpaperURL() {
        if !cur.path.hasPrefix(processedDir.path) {
            touchLock()
            if let processed = process(cur) {
                setWallpaper(processed, allSpaces: false)
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
            setWallpaper(processed, allSpaces: false)
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
