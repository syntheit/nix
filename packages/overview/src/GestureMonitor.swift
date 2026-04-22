import Foundation
import Darwin

private let kNormYOff = 36, kStateOff = 20, kStride = 96
private weak var shared: GestureMonitor?

class GestureMonitor {
    /// Called the instant 3 fingers touch — use to start async capture early
    var onPrepare: (() -> Void)?
    /// Called on each touch frame with the vertical delta (0 = start position)
    var onThreeFingerVertical: ((CGFloat) -> Void)?
    /// Called when 3 fingers lift after a vertical gesture was active
    var onThreeFingerEnd: (() -> Void)?
    /// Discrete horizontal swipes
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    private var handle: UnsafeMutableRawPointer?
    private var startY: Float = 0
    private var tracking = false
    private var verticalActive = false
    private var axisDecided = false
    private var isVertical = false
    private var lastHorizTrigger: Double = 0

    private let fullSwipe: Float = 0.22
    private let horizThreshold: Float = 0.10

    func start() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        handle = dlopen(path, RTLD_LAZY)
        guard handle != nil,
              let c = dlsym(handle, "MTDeviceCreateList"),
              let r = dlsym(handle, "MTRegisterContactFrameCallback"),
              let s = dlsym(handle, "MTDeviceStart") else { return }
        typealias C = @convention(c) () -> Unmanaged<CFArray>
        typealias F = @convention(c) (Int32, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
        typealias R = @convention(c) (UnsafeMutableRawPointer, F) -> Void
        typealias S = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        shared = self
        let devs = unsafeBitCast(c, to: C.self)().takeUnretainedValue() as [AnyObject]
        for d in devs {
            unsafeBitCast(r, to: R.self)(Unmanaged.passUnretained(d).toOpaque(), cb)
            unsafeBitCast(s, to: S.self)(Unmanaged.passUnretained(d).toOpaque(), 0)
        }
        print("[overview] gesture active (\(devs.count) device\(devs.count == 1 ? "" : "s"))")
    }

    fileprivate func process(_ data: UnsafeMutableRawPointer, count: Int32) {
        guard count == 3 else {
            if verticalActive {
                verticalActive = false
                DispatchQueue.main.async { [self] in onThreeFingerEnd?() }
            }
            tracking = false; axisDecided = false
            return
        }

        // All 3 must be touching (state 4)
        var avgY: Float = 0, avgX: Float = 0, allTouch = true
        for i in 0..<3 {
            let b = i * kStride
            if data.load(fromByteOffset: b + kStateOff, as: Int32.self) != 4 { allTouch = false }
            avgY += data.load(fromByteOffset: b + kNormYOff, as: Float.self)
            avgX += data.load(fromByteOffset: b + 32, as: Float.self)  // kNormXOff
        }
        guard allTouch else {
            if verticalActive {
                verticalActive = false
                DispatchQueue.main.async { [self] in onThreeFingerEnd?() }
            }
            tracking = false; axisDecided = false
            return
        }
        avgY /= 3; avgX /= 3

        if !tracking {
            tracking = true; startY = avgY; startX = avgX; axisDecided = false
            DispatchQueue.main.async { [self] in onPrepare?() }
            return
        }

        let dy = avgY - startY
        let dx = avgX - startX

        // Decide axis once (very low threshold for responsiveness)
        if !axisDecided {
            if abs(dy) > 0.015 && abs(dy) > abs(dx) {
                axisDecided = true; isVertical = true
            } else if abs(dx) > 0.015 && abs(dx) > abs(dy) {
                axisDecided = true; isVertical = false
            } else { return }
        }

        if isVertical {
            verticalActive = true
            let progress = CGFloat(dy / fullSwipe)
            DispatchQueue.main.async { [self] in onThreeFingerVertical?(progress) }
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            if abs(dx) > horizThreshold && now - lastHorizTrigger > 0.4 {
                lastHorizTrigger = now
                tracking = false; axisDecided = false
                DispatchQueue.main.async { [self] in dx > 0 ? onSwipeRight?() : onSwipeLeft?() }
            }
        }
    }

    private var startX: Float = 0
    deinit { if let h = handle { dlclose(h) } }
}

private func cb(_ d: Int32, _ data: UnsafeMutableRawPointer, _ n: Int32, _ t: Double, _ f: Int32) -> Int32 {
    shared?.process(data, count: n); return 0
}
