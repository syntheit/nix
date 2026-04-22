import Foundation
import Darwin

// MultitouchSupport.framework touch data (stable across macOS versions, matches MiddleClick/Jitouch)
private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32       // 4 = touching, 7 = lifted
    var fingerID: Int32
    var handID: Int32
    var normalized: MTPoint // 0..1 position on trackpad surface
    var size: MTPoint
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolutePos: MTPoint
    var zero2: Int32
    var zero3: Int32
    var density: Float
}

// Known struct layout offsets (ARM64 natural alignment)
// State and normalized position offsets are stable across macOS versions.
// Stride grew from 88 (macOS 14) to 96 (macOS 26) — Apple added fields at the end.
private let kNormalizedXOffset = 32 // Float at byte 32
private let kNormalizedYOffset = 36 // Float at byte 36
private let kStateOffset       = 20 // Int32 at byte 20
private let kTouchStride       = 96 // sizeof(MTTouch) on macOS 26 (Tahoe)

// Global reference for the C callback (MultitouchSupport callbacks have no refcon parameter)
private weak var sharedMonitor: GestureMonitor?

class GestureMonitor {
    private let onSwipeUp: () -> Void
    private let onSwipeDown: () -> Void
    private var handle: UnsafeMutableRawPointer?

    // Gesture tracking state (only accessed from the MT callback thread)
    private var fingerStartY: [Float] = [0, 0, 0] // per-finger start Y
    private var startTime: Double = 0
    private var tracking = false
    private var lastTrigger: Double = 0

    // Tuning
    private let swipeThreshold: Float = 0.10  // 10% of trackpad height
    private let perFingerMin: Float = 0.04    // each finger must move at least 4%
    private let maxSwipeDuration: Double = 0.5 // must complete within 500ms
    private let cooldown: Double = 0.4         // ignore retriggering for 400ms

    init(onSwipeUp: @escaping () -> Void, onSwipeDown: @escaping () -> Void) {
        self.onSwipeUp = onSwipeUp
        self.onSwipeDown = onSwipeDown
    }

    func start() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        handle = dlopen(path, RTLD_LAZY)
        guard handle != nil else {
            print("[overview] cannot load MultitouchSupport.framework")
            return
        }

        guard let createSym  = dlsym(handle, "MTDeviceCreateList"),
              let regSym     = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym   = dlsym(handle, "MTDeviceStart")
        else {
            print("[overview] cannot resolve MultitouchSupport symbols")
            return
        }

        typealias CreateFn   = @convention(c) () -> Unmanaged<CFArray>
        typealias CallbackFn = @convention(c) (Int32, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
        typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, CallbackFn) -> Void
        typealias StartFn    = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

        let create   = unsafeBitCast(createSym,  to: CreateFn.self)
        let register = unsafeBitCast(regSym,     to: RegisterFn.self)
        let start    = unsafeBitCast(startSym,   to: StartFn.self)

        sharedMonitor = self

        let devices = create().takeUnretainedValue() as [AnyObject]
        for device in devices {
            let ptr = Unmanaged.passUnretained(device).toOpaque()
            register(ptr, mtCallback)
            start(ptr, 0)
        }
        print("[overview] gesture monitoring active (\(devices.count) device\(devices.count == 1 ? "" : "s"))")
    }

    fileprivate func processTouches(_ data: UnsafeMutableRawPointer, count: Int32) {
        let n = Int(count)

        // Must be exactly 3 fingers
        guard n == 3 else {
            tracking = false
            return
        }

        // Read per-finger positions — all must be actively touching (state 4)
        var ys: [Float] = []
        var allTouching = true
        for i in 0..<3 {
            let base = i * kTouchStride
            let state = data.load(fromByteOffset: base + kStateOffset, as: Int32.self)
            let ny    = data.load(fromByteOffset: base + kNormalizedYOffset, as: Float.self)
            ys.append(ny)
            if state != 4 { allTouching = false }
        }

        guard allTouching else {
            tracking = false
            return
        }

        let now = ProcessInfo.processInfo.systemUptime

        if !tracking {
            tracking = true
            fingerStartY = ys
            startTime = now
            return
        }

        // Timeout — not a quick swipe
        if now - startTime > maxSwipeDuration {
            tracking = false
            return
        }

        // Check that ALL fingers moved in the same direction (not palm + 2-finger scroll)
        let avgDelta = (0..<3).map { ys[$0] - fingerStartY[$0] }.reduce(0, +) / 3
        let allMovedSameDir = (0..<3).allSatisfy { i in
            let d = ys[i] - fingerStartY[i]
            return abs(d) >= perFingerMin && (d > 0) == (avgDelta > 0)
        }

        if allMovedSameDir, abs(avgDelta) > swipeThreshold, now - lastTrigger > cooldown {
            lastTrigger = now
            tracking = false
            let handler = avgDelta > 0 ? onSwipeUp : onSwipeDown
            DispatchQueue.main.async { handler() }
        }
    }

    deinit {
        if let h = handle { dlclose(h) }
    }
}

// Plain C callback bridged to the shared GestureMonitor instance
private func mtCallback(
    _ device: Int32,
    _ data: UnsafeMutableRawPointer,
    _ nFingers: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    sharedMonitor?.processTouches(data, count: nFingers)
    return 0
}
