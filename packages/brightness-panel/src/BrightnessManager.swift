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

    func adjustBrightness(by delta: Float) {
        let newVal = max(0, min(1, getBrightness() + delta))
        setBrightness(newVal)
        refresh()
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
