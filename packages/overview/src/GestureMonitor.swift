import Foundation
import Darwin

private let kNormXOff = 32, kNormYOff = 36, kStateOff = 20, kStride = 96
private weak var sharedMonitor: GestureMonitor?

class GestureMonitor {
    // Discrete callbacks (horizontal swipes, dismiss)
    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}

    // Continuous vertical gesture callbacks (1:1 tracking)
    var onVerticalBegin: (() -> Void)?
    var onVerticalUpdate: ((CGFloat) -> Void)?   // progress: 0 = start, 1 = fully open
    var onVerticalEnd: ((CGFloat) -> Void)?       // final progress on release
    var onDismissUpdate: ((CGFloat) -> Void)?     // progress for downward dismiss
    var onDismissEnd: ((CGFloat) -> Void)?

    private var handle: UnsafeMutableRawPointer?

    // Tracking state
    private var startX: [Float] = [0, 0, 0]
    private var startY: [Float] = [0, 0, 0]
    private var startTime: Double = 0
    private var tracking = false
    private var gestureActive = false  // continuous gesture in progress
    private var lastDiscreteTrigger: Double = 0
    private var dominantAxis: Axis? = nil

    private enum Axis { case horizontal, vertical }

    // Tuning
    private let lockDistance: Float = 0.03        // 3% to lock axis
    private let fullSwipeDistance: Float = 0.20   // 20% of trackpad = full overview
    private let discreteThreshold: Float = 0.10  // for horizontal swipes
    private let discreteCooldown: Double = 0.4
    private let perFingerMin: Float = 0.03

    func start() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        handle = dlopen(path, RTLD_LAZY)
        guard handle != nil else { return }
        guard let cSym = dlsym(handle, "MTDeviceCreateList"),
              let rSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let sSym = dlsym(handle, "MTDeviceStart") else { return }

        typealias CreateFn = @convention(c) () -> Unmanaged<CFArray>
        typealias CbFn     = @convention(c) (Int32, UnsafeMutableRawPointer, Int32, Double, Int32) -> Int32
        typealias RegFn    = @convention(c) (UnsafeMutableRawPointer, CbFn) -> Void
        typealias StartFn  = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

        sharedMonitor = self
        let devices = unsafeBitCast(cSym, to: CreateFn.self)().takeUnretainedValue() as [AnyObject]
        for d in devices {
            unsafeBitCast(rSym, to: RegFn.self)(Unmanaged.passUnretained(d).toOpaque(), mtCb)
            unsafeBitCast(sSym, to: StartFn.self)(Unmanaged.passUnretained(d).toOpaque(), 0)
        }
        print("[overview] gesture monitoring active (\(devices.count) device\(devices.count == 1 ? "" : "s"))")
    }

    fileprivate func processTouches(_ data: UnsafeMutableRawPointer, count: Int32) {
        guard count == 3 else {
            if gestureActive { endGesture() }
            tracking = false
            dominantAxis = nil
            return
        }

        var xs: [Float] = [], ys: [Float] = [], allTouch = true
        for i in 0..<3 {
            let b = i * kStride
            if data.load(fromByteOffset: b + kStateOff, as: Int32.self) != 4 { allTouch = false }
            xs.append(data.load(fromByteOffset: b + kNormXOff, as: Float.self))
            ys.append(data.load(fromByteOffset: b + kNormYOff, as: Float.self))
        }

        guard allTouch else {
            if gestureActive { endGesture() }
            tracking = false
            dominantAxis = nil
            return
        }

        if !tracking {
            tracking = true
            startX = xs; startY = ys
            startTime = ProcessInfo.processInfo.systemUptime
            dominantAxis = nil
            return
        }

        let dx = (0..<3).map { xs[$0] - startX[$0] }.reduce(0, +) / 3
        let dy = (0..<3).map { ys[$0] - startY[$0] }.reduce(0, +) / 3

        // Lock axis once movement exceeds threshold
        if dominantAxis == nil {
            if abs(dy) > lockDistance && abs(dy) > abs(dx) * 1.5 {
                dominantAxis = .vertical
            } else if abs(dx) > lockDistance && abs(dx) > abs(dy) * 1.5 {
                dominantAxis = .horizontal
            } else {
                return  // not enough movement to determine axis
            }
        }

        switch dominantAxis {
        case .vertical:
            handleVertical(dy: dy, ys: ys)
        case .horizontal:
            handleHorizontal(dx: dx, xs: xs)
        case .none:
            break
        }
    }

    private func handleVertical(dy: Float, ys: [Float]) {
        let progress = CGFloat(dy / fullSwipeDistance)

        if dy > 0 {
            // Upward — show overview (continuous tracking)
            if !gestureActive {
                gestureActive = true
                DispatchQueue.main.async { [self] in onVerticalBegin?() }
            }
            DispatchQueue.main.async { [self] in
                onVerticalUpdate?(min(max(progress, 0), 1.5))
            }
        } else if gestureActive {
            // Downward while active — dismiss tracking
            let dismissProgress = CGFloat(-dy / fullSwipeDistance)
            DispatchQueue.main.async { [self] in
                onDismissUpdate?(min(max(dismissProgress, 0), 1.5))
            }
        }
    }

    private func handleHorizontal(dx: Float, xs: [Float]) {
        let now = ProcessInfo.processInfo.systemUptime
        guard abs(dx) > discreteThreshold, now - lastDiscreteTrigger > discreteCooldown else { return }
        let allSameDir = (0..<3).allSatisfy {
            let d = xs[$0] - startX[$0]
            return abs(d) >= perFingerMin && (d > 0) == (dx > 0)
        }
        guard allSameDir else { return }
        lastDiscreteTrigger = now
        tracking = false
        dominantAxis = nil
        DispatchQueue.main.async { [self] in dx > 0 ? onSwipeRight() : onSwipeLeft() }
    }

    private func endGesture() {
        gestureActive = false
        DispatchQueue.main.async { [self] in
            onVerticalEnd?(0)
        }
    }

    deinit { if let h = handle { dlclose(h) } }
}

private func mtCb(_ d: Int32, _ data: UnsafeMutableRawPointer, _ n: Int32, _ t: Double, _ f: Int32) -> Int32 {
    sharedMonitor?.processTouches(data, count: n)
    return 0
}
