import Foundation
import IOBluetooth
import IOKit

class BluetoothManager: ObservableObject {
    struct Device: Identifiable {
        let id: String  // MAC address
        let name: String
        let isConnected: Bool
        let majorClass: UInt32
        let minorClass: UInt32
        var batteryLevel: Int?

        var icon: String {
            // Major class 0x04 = Audio/Video
            if majorClass == 4 { return "headphones" }
            // Major class 0x05 = Peripheral
            if majorClass == 5 {
                if minorClass == 0x40 || minorClass == 1 { return "keyboard" }
                if minorClass == 0x80 || minorClass == 2 { return "computermouse" }
                return "gamecontroller"
            }
            // Major class 0x01 = Computer
            if majorClass == 1 { return "desktopcomputer" }
            // Major class 0x02 = Phone
            if majorClass == 2 { return "iphone" }
            return "wave.3.right"
        }
    }

    @Published var isPowered = false
    @Published var devices: [Device] = []
    @Published var isLoading = false

    // Private API function types
    private typealias PowerGetter = @convention(c) () -> CInt
    private typealias PowerSetter = @convention(c) (CInt) -> Void

    private var powerGetter: PowerGetter?
    private var powerSetter: PowerSetter?

    init() {
        loadPrivateAPIs()
        refresh()
    }

    // MARK: - Private API Loading

    private func loadPrivateAPIs() {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) else { return }

        if let sym = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") {
            powerGetter = unsafeBitCast(sym, to: PowerGetter.self)
        }
        if let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") {
            powerSetter = unsafeBitCast(sym, to: PowerSetter.self)
        }
    }

    // MARK: - Power

    func togglePower() {
        let newState: CInt = isPowered ? 0 : 1
        powerSetter?(newState)
        // Power state change takes a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Refresh

    func refresh() {
        isPowered = powerGetter?() != 0

        guard isPowered else {
            devices = []
            return
        }

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            devices = []
            return
        }

        let batteries = getBatteryLevels()

        var seen = Set<String>()
        devices = paired.compactMap { dev in
            guard let name = dev.name, !name.isEmpty else { return nil }
            let addr = dev.addressString ?? ""
            // AirPods register as multiple profiles (Classic + LE) — deduplicate by address
            guard !seen.contains(addr) else { return nil }
            seen.insert(addr)
            let battery = batteries[name]
            return Device(
                id: addr,
                name: name,
                isConnected: dev.isConnected(),
                majorClass: UInt32(dev.deviceClassMajor),
                minorClass: UInt32(dev.deviceClassMinor),
                batteryLevel: battery
            )
        }.sorted { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            return a.name < b.name
        }
    }

    // MARK: - Connect / Disconnect

    func connect(_ device: Device) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }
            btDevice.openConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.refresh()
                self?.isLoading = false
            }
        }
    }

    func disconnect(_ device: Device) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
                DispatchQueue.main.async { self?.isLoading = false }
                return
            }
            // Retry disconnect (can be unreliable)
            for _ in 0..<5 {
                btDevice.closeConnection()
                Thread.sleep(forTimeInterval: 0.3)
                if !btDevice.isConnected() { break }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
                self?.isLoading = false
            }
        }
    }

    // MARK: - Battery via IOKit

    private func getBatteryLevels() -> [String: Int] {
        var result: [String: Int] = [:]

        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            guard let batteryRef = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, nil, 0),
                  let battery = batteryRef.takeRetainedValue() as? Int else { continue }

            let name: String
            if let productRef = IORegistryEntryCreateCFProperty(service, "Product" as CFString, nil, 0),
               let product = productRef.takeRetainedValue() as? String {
                name = product
            } else {
                continue
            }

            result[name] = battery
        }

        return result
    }
}
