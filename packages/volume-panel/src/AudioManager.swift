import CoreAudio
import AudioToolbox
import Foundation

class AudioManager: ObservableObject {
    struct OutputDevice: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transportType: UInt32
        var isDefault: Bool

        var icon: String {
            switch transportType {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return "headphones"
            case kAudioDeviceTransportTypeBuiltIn:
                return "laptopcomputer"
            case kAudioDeviceTransportTypeUSB:
                return "cable.connector"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
                return "tv"
            default:
                return "speaker.wave.2"
            }
        }
    }

    @Published var volume: Float = 0
    @Published var isMuted: Bool = false
    @Published var devices: [OutputDevice] = []
    @Published var currentDeviceName: String = ""

    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refresh()
        installListeners()
    }

    func refresh() {
        let device = volumeTargetDevice()
        volume = getVolume(device)
        isMuted = getMuted(device)
        devices = getOutputDevices()
        let defaultDev = defaultOutputDevice()
        let defaultName = getDeviceName(defaultDev)
        // Show the real device name, not the aggregate
        if defaultName.hasSuffix("(EQ)") {
            currentDeviceName = String(defaultName.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else {
            currentDeviceName = defaultName
        }
    }

    // MARK: - Volume Control

    /// Returns the device whose volume we should control.
    /// When EQ is active, the default device is an aggregate wrapping BlackHole
    /// which doesn't expose volume controls. We need the real device underneath.
    private func volumeTargetDevice() -> AudioDeviceID {
        let defaultDev = defaultOutputDevice()
        let name = getDeviceName(defaultDev)
        // If the default is an EQ aggregate, find the real device via eq daemon config
        if name.hasSuffix("(EQ)") {
            if let realDevice = findRealDeviceFromEQ() {
                return realDevice
            }
            // Fallback: find a device whose name matches without "(EQ)"
            let realName = String(name.dropLast(5)).trimmingCharacters(in: .whitespaces)
            let allDevices = getAllDeviceIDs()
            for id in allDevices {
                let n = getDeviceName(id)
                if n == realName { return id }
            }
        }
        return defaultDev
    }

    /// Ask the eq daemon for the real device UID and find it by UID
    private func findRealDeviceFromEQ() -> AudioDeviceID? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let response = sendIPC("status", socketPath: "\(home)/.config/eq/eq.sock"),
              let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceName = json["device"] as? String else { return nil }

        let allDevices = getAllDeviceIDs()
        for id in allDevices {
            if getDeviceName(id) == deviceName { return id }
        }
        return nil
    }

    private func getAllDeviceIDs() -> [AudioDeviceID] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size, &ids)
        return ids
    }

    func adjustVolume(by delta: Float) {
        let device = volumeTargetDevice()
        if getMuted(device) { setMuted(device, false) }
        let newVol = max(0, min(1, getVolume(device) + delta))
        setVolume(device, newVol)
        refresh()
    }

    func toggleMute() {
        let device = volumeTargetDevice()
        setMuted(device, !getMuted(device))
        refresh()
    }

    func setOutputDevice(_ deviceID: AudioDeviceID) {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        refresh()
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDevice() -> AudioDeviceID {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getVolume(_ device: AudioDeviceID) -> Float {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &propAddr, 0, nil, &size, &vol)
        return vol
    }

    private func setVolume(_ device: AudioDeviceID, _ vol: Float) {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var v = vol
        AudioObjectSetPropertyData(device, &propAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    private func getMuted(_ device: AudioDeviceID) -> Bool {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &propAddr, 0, nil, &size, &muted)
        return muted != 0
    }

    private func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var val: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &propAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
    }

    private func getOutputDevices() -> [OutputDevice] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &size, &ids)

        let defaultID = defaultOutputDevice()

        return ids.compactMap { id in
            // Check for output streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { return nil }

            let name = getDeviceName(id)
            let transport = getTransportType(id)

            // Skip aggregate devices created by EQ (they contain "EQ" in name)
            if name.contains("(EQ)") { return nil }

            return OutputDevice(id: id, name: name, transportType: transport, isDefault: id == defaultID)
        }
    }

    private func getDeviceName(_ device: AudioDeviceID) -> String {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(device, &propAddr, 0, nil, &size, &name)
        return name as String
    }

    private func getTransportType(_ device: AudioDeviceID) -> UInt32 {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &propAddr, 0, nil, &size, &transport)
        return transport
    }

    // MARK: - Listeners

    private func installListeners() {
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        deviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &volAddr, DispatchQueue.main, block)
    }

    // MARK: - EQ IPC

    func eqStatus() -> (enabled: Bool, bass: Float, mid: Float, treble: Float)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let response = sendIPC("status", socketPath: "\(home)/.config/eq/eq.sock"),
              let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return (
            enabled: json["enabled"] as? Bool ?? false,
            bass: (json["bass"] as? NSNumber)?.floatValue ?? 0,
            mid: (json["mid"] as? NSNumber)?.floatValue ?? 0,
            treble: (json["treble"] as? NSNumber)?.floatValue ?? 0
        )
    }

    func eqCommand(_ cmd: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = sendIPC(cmd, socketPath: "\(home)/.config/eq/eq.sock")
    }
}
