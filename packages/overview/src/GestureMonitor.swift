import Foundation
import Darwin

private let kNormYOff = 36, kStateOff = 20, kStride = 96
private weak var shared: GestureMonitor?

class GestureMonitor {
    /// Called the instant 3+ fingers touch — use to start async capture early
    var onPrepare: (() -> Void)?
    /// Called on each touch frame with the vertical delta (0 = start position)
    var onThreeFingerVertical: ((CGFloat) -> Void)?
    /// Called when fingers lift after a vertical gesture was active
    var onThreeFingerEnd: (() -> Void)?
    /// Called on each touch frame with the horizontal delta (continuous, normalized)
    var onThreeFingerHorizontal: ((CGFloat) -> Void)?
    /// Called when fingers lift after a horizontal gesture was active
    var onThreeFingerHorizEnd: (() -> Void)?

    /// Current horizontal velocity in normalized units/sec (read on end)
    private(set) var currentVelocityX: CGFloat = 0

    private var handle: UnsafeMutableRawPointer?
    private var startY: Float = 0
    private var startX: Float = 0
    private var tracking = false
    private var verticalActive = false
    private var horizontalActive = false
    private var axisDecided = false
    private var isVertical = false

    // Velocity tracking
    private var lastDx: Float = 0
    private var lastDxTime: Double = 0

    private let fullSwipe: Float = 0.22

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
        // Support 3 or 4 finger gestures
        guard count == 3 || count == 4 else {
            if verticalActive {
                verticalActive = false
                DispatchQueue.main.async { [self] in onThreeFingerEnd?() }
            }
            if horizontalActive {
                horizontalActive = false
                DispatchQueue.main.async { [self] in onThreeFingerHorizEnd?() }
            }
            tracking = false; axisDecided = false
            currentVelocityX = 0
            return
        }

        let n = Int(count)

        // All fingers must be touching (state 4)
        var avgY: Float = 0, avgX: Float = 0, allTouch = true
        for i in 0..<n {
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
            if horizontalActive {
                horizontalActive = false
                DispatchQueue.main.async { [self] in onThreeFingerHorizEnd?() }
            }
            tracking = false; axisDecided = false
            currentVelocityX = 0
            return
        }
        avgY /= Float(n); avgX /= Float(n)

        if !tracking {
            tracking = true; startY = avgY; startX = avgX; axisDecided = false
            lastDx = 0; lastDxTime = 0; currentVelocityX = 0
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
            horizontalActive = true

            // Track velocity
            let now = ProcessInfo.processInfo.systemUptime
            if lastDxTime > 0 && now - lastDxTime > 0.001 {
                let rawVel = CGFloat((dx - lastDx) / Float(now - lastDxTime) / fullSwipe)
                // Smooth with previous to reduce noise
                currentVelocityX = currentVelocityX * 0.3 + rawVel * 0.7
            }
            lastDx = dx; lastDxTime = now

            let progress = CGFloat(dx / fullSwipe)
            DispatchQueue.main.async { [self] in onThreeFingerHorizontal?(progress) }
        }
    }

    deinit { if let h = handle { dlclose(h) } }
}

private func cb(_ d: Int32, _ data: UnsafeMutableRawPointer, _ n: Int32, _ t: Double, _ f: Int32) -> Int32 {
    shared?.process(data, count: n); return 0
}
