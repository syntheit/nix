import AppKit
import Foundation

class BrightnessManager: ObservableObject {
    @Published var brightness: Float = 0

    // DisplayServices loaded at runtime (private framework, no compile-time link needed)
    private let dsHandle: UnsafeMutableRawPointer?

    init() {
        dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        refresh()
    }

    func refresh() {
        brightness = getBrightness()
    }

    /// Level the display is heading to (equals `brightness` when idle).
    var target: Float { fadeTimer != nil ? goal : getBrightness() }
    private var goal: Float = 0
    private var fadeTimer: DispatchSourceTimer?
    private var fadeGen = 0
    private let fadeQueue = DispatchQueue(label: "brightness.fade", qos: .userInteractive)
    private var activity: NSObjectProtocol?

    /// Latest press wins: a new call cancels any in-flight fade and starts a new
    /// one from the display's actual current level toward the new target.
    func adjustBrightness(by delta: Float) {
        goal = max(0, min(1, target + delta))
        fade(to: goal)
    }

    // The fade runs on a strict dispatch timer off the main thread: RunLoop timers
    // in this background (accessory) app get coalesced/throttled to ~30-70ms gaps,
    // which turned the ramp into a handful of visible jumps.
    private func fade(to goal: Float, duration: TimeInterval = 0.25) {
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeGen += 1
        let gen = fadeGen
        let from = getBrightness()
        if abs(goal - from) < 0.002 || duration <= 0 {
            setBrightness(goal)
            refresh()
            return
        }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "brightness fade")
        }
        let start = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: fadeQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self, self.fadeGen == gen else { return }
            let p = min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
            let eased = Float(0.5 - 0.5 * cos(Double.pi * p))  // ease-in-out (sine)
            let v = p >= 1 ? goal : from + (goal - from) * eased
            self.setBrightness(v)
            DispatchQueue.main.async {
                guard self.fadeGen == gen else { return }
                self.brightness = v
                if p >= 1 {
                    self.fadeTimer?.cancel(); self.fadeTimer = nil
                    if let a = self.activity { ProcessInfo.processInfo.endActivity(a); self.activity = nil }
                }
            }
            if p >= 1 { timer.cancel() }
        }
        fadeTimer = timer
        timer.resume()
    }

    private func getBrightness() -> Float {
        guard let dsHandle, let sym = dlsym(dsHandle, "DisplayServicesGetBrightness") else { return 0 }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        var val: Float = 0
        _ = unsafeBitCast(sym, to: Fn.self)(CGMainDisplayID(), &val)
        return val
    }

    private func setBrightness(_ value: Float) {
        guard let dsHandle, let sym = dlsym(dsHandle, "DisplayServicesSetBrightness") else { return }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        _ = unsafeBitCast(sym, to: Fn.self)(CGMainDisplayID(), value)
    }
}

// MARK: - Keyboard Backlight (CoreBrightness.framework / KeyboardBrightnessClient)
//
// CoreBrightness is a private framework. We load it at runtime, instantiate the
// `KeyboardBrightnessClient` ObjC class via NSClassFromString, look up method
// IMPs and call them via @convention(c) function pointers — same pattern the
// display side uses with DisplayServices.
//
// Public selectors (verified against runtime headers):
//   -(id)copyKeyboardBacklightIDs
//   -(float)brightnessForKeyboard:(unsigned long long)kbid
//   -(BOOL)setBrightness:(float)b forKeyboard:(unsigned long long)kbid

private typealias IdsIMP = @convention(c) (NSObject, Selector) -> NSArray?
private typealias GetIMP = @convention(c) (NSObject, Selector, UInt64) -> Float
private typealias SetIMP = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool

class KeyboardBacklightManager: ObservableObject {
    @Published var brightness: Float = 0

    private var client: NSObject?
    private var kbid: UInt64 = 0
    private var getImpl: GetIMP?
    private var setImpl: SetIMP?
    private let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private let setSel = NSSelectorFromString("setBrightness:forKeyboard:")

    private func log(_ s: String) {
        FileHandle.standardError.write(Data("kb-backlight: \(s)\n".utf8))
    }

    init() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil else {
            log("dlopen CoreBrightness failed")
            return
        }
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            log("NSClassFromString(KeyboardBrightnessClient) returned nil")
            return
        }
        let c = cls.init()
        self.client = c
        log("instantiated KeyboardBrightnessClient: \(type(of: c))")

        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if let imp = c.method(for: idsSel) {
            let fn = unsafeBitCast(imp, to: IdsIMP.self)
            if let ids = fn(c, idsSel) {
                log("copyKeyboardBacklightIDs returned \(ids.count) entries: \(ids)")
                for any in ids {
                    if let n = any as? NSNumber {
                        self.kbid = n.uint64Value
                        log("selected kbid=\(self.kbid)")
                        break
                    } else {
                        log("entry is not NSNumber: \(type(of: any))")
                    }
                }
            } else {
                log("copyKeyboardBacklightIDs returned nil")
            }
        } else {
            log("no IMP for copyKeyboardBacklightIDs")
        }

        if let imp = c.method(for: getSel) {
            self.getImpl = unsafeBitCast(imp, to: GetIMP.self)
        } else {
            log("no IMP for brightnessForKeyboard:")
        }
        if let imp = c.method(for: setSel) {
            self.setImpl = unsafeBitCast(imp, to: SetIMP.self)
        } else {
            log("no IMP for setBrightness:forKeyboard:")
        }

        refresh()
        log("init complete: kbid=\(kbid), brightness=\(brightness)")
    }

    func refresh() {
        guard let c = client, let fn = getImpl else { return }
        brightness = fn(c, getSel, kbid)
    }

    func adjust(by delta: Float) {
        guard let c = client, let setFn = setImpl else {
            log("adjust noop: client=\(client != nil), setImpl=\(setImpl != nil)")
            return
        }
        refresh()
        let new = max(0, min(1, brightness + delta))
        let result = setFn(c, setSel, new, kbid)
        log("adjust delta=\(delta) brightness=\(brightness)->\(new) kbid=\(kbid) result=\(result)")
        refresh()
    }
}
