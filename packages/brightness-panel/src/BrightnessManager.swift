import AppKit

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

    // MARK: - DisplayServices

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
