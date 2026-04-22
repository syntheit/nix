import Foundation
import AVFAudio
import CoreAudio
import AudioToolbox

// MARK: - Configuration

struct EQConfig: Codable {
    var enabled: Bool = true
    var bass: Float = 7.4
    var mid: Float = 0.0
    var treble: Float = 0.0
    var realDeviceUID: String? = nil

    static var configDir: String { "\(NSHomeDirectory())/.config/eq" }
    static var configPath: String { "\(configDir)/config.json" }
    static var socketPath: String { "\(configDir)/eq.sock" }

    static func load() -> EQConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(EQConfig.self, from: data) else {
            return EQConfig()
        }
        return config
    }

    func save() {
        try? FileManager.default.createDirectory(
            atPath: EQConfig.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: URL(fileURLWithPath: EQConfig.configPath))
        }
    }
}

// MARK: - CoreAudio Helpers

let kBlackHoleUID = "BlackHole2ch_UID"

func getPropertyData<T>(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    var size = UInt32(MemoryLayout<T>.size)
    let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { value.deallocate() }
    let status = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, value)
    guard status == noErr else { return nil }
    return value.pointee
}

func getDefaultOutputDevice() -> AudioObjectID {
    return getPropertyData(AudioObjectID(kAudioObjectSystemObject),
                           selector: kAudioHardwarePropertyDefaultOutputDevice) ?? 0
}

func setDefaultOutputDevice(_ deviceID: AudioObjectID) {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var id = deviceID
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                               &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)

    // Also set default system output device (system sounds)
    var sysAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                               &sysAddr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
}

func getStringProperty(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
    var ref: Unmanaged<CFString>?
    let status = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &ref)
    guard status == noErr, let cfStr = ref else { return nil }
    return cfStr.takeRetainedValue() as String
}

func getDeviceName(_ deviceID: AudioObjectID) -> String {
    return getStringProperty(deviceID, selector: kAudioObjectPropertyName) ?? "Unknown"
}

func getDeviceUID(_ deviceID: AudioObjectID) -> String {
    return getStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
}

func getDeviceTransportType(_ deviceID: AudioObjectID) -> UInt32 {
    return getPropertyData(deviceID, selector: kAudioDevicePropertyTransportType) ?? 0
}

func getAllOutputDevices() -> [(id: AudioObjectID, name: String, uid: String, transport: UInt32)] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var devices = [AudioObjectID](repeating: 0, count: count)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices)

    return devices.compactMap { deviceID in
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return nil }
        let bufPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(streamSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &streamAddr, 0, nil, &streamSize, bufPtr) == noErr else { return nil }
        let bufList = bufPtr.assumingMemoryBound(to: AudioBufferList.self)
        let bufs = UnsafeMutableAudioBufferListPointer(bufList)
        let channels = bufs.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channels > 0 else { return nil }
        return (deviceID, getDeviceName(deviceID), getDeviceUID(deviceID), getDeviceTransportType(deviceID))
    }
}

func findDeviceByUID(_ uid: String) -> AudioObjectID? {
    return getAllOutputDevices().first { $0.uid == uid }?.id
}

func isBluetoothDevice(_ transportType: UInt32) -> Bool {
    let blue = UInt32(0x626C7565) // 'blue'
    let blea = UInt32(0x626C6561) // 'blea'
    return transportType == blue || transportType == blea
}

func isVirtualDevice(_ transportType: UInt32) -> Bool {
    let virt = UInt32(0x76697274) // 'virt'
    let grup = UInt32(0x67727570) // 'grup' (aggregate)
    return transportType == virt || transportType == grup
}

func isEQEligible(_ deviceID: AudioObjectID) -> Bool {
    let transport = getDeviceTransportType(deviceID)
    if isBluetoothDevice(transport) { return false }
    if isVirtualDevice(transport) { return false }
    return true
}

func transportName(_ t: UInt32) -> String {
    if isBluetoothDevice(t) { return "bluetooth" }
    if isVirtualDevice(t) { return "virtual" }
    let builtIn = UInt32(0x626C746E) // 'bltn'
    if t == builtIn { return "built-in" }
    let usb = UInt32(0x75736220) // 'usb '
    if t == usb { return "usb" }
    return "other"
}

// MARK: - Aggregate Device

func createNamedAggregate(name: String, uid: String, subDeviceUID: String) -> AudioObjectID? {
    let desc: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: name,
        kAudioAggregateDeviceUIDKey as String: uid,
        kAudioAggregateDeviceIsPrivateKey as String: false,
        kAudioAggregateDeviceSubDeviceListKey as String: [
            [kAudioSubDeviceUIDKey as String: subDeviceUID]
        ]
    ]
    var aggregateID: AudioObjectID = 0
    let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateID)
    guard status == noErr else { return nil }
    return aggregateID
}

func destroyAggregate(_ deviceID: AudioObjectID) {
    AudioHardwareDestroyAggregateDevice(deviceID)
}

// MARK: - EQ Engine

class EQEngine {
    private var engine: AVAudioEngine?
    private var eq: AVAudioUnitEQ?
    private(set) var isRunning = false
    private(set) var blackholeID: AudioObjectID = 0
    private(set) var outputID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    var config: EQConfig

    init(config: EQConfig) {
        self.config = config
    }

    func start(blackhole: AudioObjectID, output: AudioObjectID, outputName: String) throws {
        stop()

        blackholeID = blackhole
        outputID = output

        // Create a named aggregate wrapping BlackHole so the menu bar shows a nice name
        let aggName = "\(outputName) (EQ)"
        if let agg = createNamedAggregate(name: aggName, uid: "eq-aggregate-device",
                                           subDeviceUID: kBlackHoleUID) {
            aggregateID = agg
        }

        // Set system output to speakers FIRST so outputNode binds to real hardware
        setDefaultOutputDevice(output)
        Thread.sleep(forTimeInterval: 0.1)

        let eng = AVAudioEngine()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)

        // Configure EQ bands
        eqNode.bands[0].filterType = .lowShelf
        eqNode.bands[0].frequency = 250
        eqNode.bands[0].gain = config.bass
        eqNode.bands[0].bypass = false

        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 1000
        eqNode.bands[1].bandwidth = 1.5
        eqNode.bands[1].gain = config.mid
        eqNode.bands[1].bypass = false

        eqNode.bands[2].filterType = .highShelf
        eqNode.bands[2].frequency = 4000
        eqNode.bands[2].gain = config.treble
        eqNode.bands[2].bypass = false

        // Set input device to BlackHole
        var bhID = blackhole
        let inputAU = eng.inputNode.audioUnit!
        AudioUnitSetProperty(inputAU, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &bhID,
                             UInt32(MemoryLayout<AudioObjectID>.size))

        // Enable input on the AUHAL unit
        var enableIO: UInt32 = 1
        AudioUnitSetProperty(inputAU, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1, &enableIO,
                             UInt32(MemoryLayout<UInt32>.size))

        eng.attach(eqNode)

        let inputFormat = eng.inputNode.outputFormat(forBus: 0)
        eng.connect(eng.inputNode, to: eqNode, format: inputFormat)
        eng.connect(eqNode, to: eng.mainMixerNode, format: inputFormat)

        eng.prepare()
        try eng.start()

        // NOW redirect system output to the named aggregate (wraps BlackHole)
        Thread.sleep(forTimeInterval: 0.1)
        if aggregateID != 0 {
            setDefaultOutputDevice(aggregateID)
        } else {
            setDefaultOutputDevice(blackhole)
        }
        Thread.sleep(forTimeInterval: 0.1)

        engine = eng
        eq = eqNode
        isRunning = true

        // Handle hardware configuration changes (sample rate, device disconnect)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: eng, queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.isRunning else { return }
                fputs("eq: audio configuration changed, restarting engine\n", stderr)
                self.isRunning = false
                // The engine already stopped itself — just need to restart
                do {
                    try self.engine?.start()
                    self.isRunning = true
                } catch {
                    fputs("eq: failed to restart after config change: \(error)\n", stderr)
                    self.stop()
                }
            }
        }
    }

    func stop() {
        engine?.stop()
        engine = nil
        eq = nil
        // Restore real device BEFORE destroying the aggregate so macOS doesn't
        // auto-switch to a random device when the aggregate disappears
        if outputID != 0 {
            setDefaultOutputDevice(outputID)
        }
        if aggregateID != 0 {
            destroyAggregate(aggregateID)
            aggregateID = 0
        }
        isRunning = false
    }

    func updateEQ() {
        guard let eq = eq else { return }
        eq.bands[0].gain = config.bass
        eq.bands[1].gain = config.mid
        eq.bands[2].gain = config.treble
    }
}

// MARK: - Daemon

class EQDaemon {
    var config: EQConfig
    let engine: EQEngine
    var realDeviceID: AudioObjectID = 0
    var blackholeID: AudioObjectID = 0
    var isRedirecting = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        config = EQConfig.load()
        engine = EQEngine(config: config)
    }

    func start() {
        // Clean up any stale aggregate from a previous crash
        if let staleAgg = findDeviceByUID("eq-aggregate-device") {
            let currentDefault = getDefaultOutputDevice()
            if getDeviceUID(currentDefault) == "eq-aggregate-device" {
                // Restore real device first
                if let uid = config.realDeviceUID, let id = findDeviceByUID(uid) {
                    setDefaultOutputDevice(id)
                }
            }
            destroyAggregate(staleAgg)
            Thread.sleep(forTimeInterval: 0.2)
        }

        guard let bhID = findDeviceByUID(kBlackHoleUID) else {
            fputs("eq: BlackHole 2ch not found. Install it: brew install --cask blackhole-2ch\n", stderr)
            exit(1)
        }
        blackholeID = bhID

        // Determine the real output device
        let currentDefault = getDefaultOutputDevice()
        let currentUID = getDeviceUID(currentDefault)
        if currentUID == kBlackHoleUID || currentUID == "eq-aggregate-device" {
            // Already redirected — recover real device from config
            if let uid = config.realDeviceUID, let id = findDeviceByUID(uid) {
                realDeviceID = id
            } else {
                // Fallback: find first non-virtual output device
                realDeviceID = getAllOutputDevices().first { !isVirtualDevice($0.transport) }?.id ?? 0
            }
        } else {
            realDeviceID = currentDefault
        }

        config.realDeviceUID = getDeviceUID(realDeviceID)
        config.save()

        // Start EQ if eligible
        if config.enabled && isEQEligible(realDeviceID) {
            activate()
        }

        // Monitor device changes
        installDeviceListener()

        // Listen for IPC
        startIPCServer()

        // Handle signals for clean shutdown
        installSignalHandlers()

        // Keep running
        RunLoop.current.run()
    }

    func activate() {
        guard !engine.isRunning else { return }
        let deviceName = getDeviceName(realDeviceID)
        isRedirecting = true
        do {
            try engine.start(blackhole: blackholeID, output: realDeviceID, outputName: deviceName)
            fputs("eq: activated — \(deviceName)\n", stderr)
        } catch {
            fputs("eq: failed to start engine: \(error)\n", stderr)
            setDefaultOutputDevice(realDeviceID)
        }
        // Delay clearing the flag so async device-change callbacks don't re-enter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRedirecting = false
        }
    }

    func deactivate() {
        guard engine.isRunning else { return }
        isRedirecting = true
        engine.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRedirecting = false
        }
        fputs("eq: deactivated\n", stderr)
    }

    func handleDeviceChange() {
        let currentDefault = getDefaultOutputDevice()
        let currentUID = getDeviceUID(currentDefault)

        // Ignore changes we caused
        if isRedirecting { return }

        // If something else changed the default away from our devices, that's a new device
        if currentUID != kBlackHoleUID && currentUID != "eq-aggregate-device" {
            realDeviceID = currentDefault
            config.realDeviceUID = getDeviceUID(realDeviceID)
            config.save()

            if config.enabled && isEQEligible(realDeviceID) {
                activate()
            } else {
                deactivate()
            }
        }
    }

    func installDeviceListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleDeviceChange() }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr,
            DispatchQueue.main, block)
    }

    func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { _ in
            // Restore real device on exit
            let config = EQConfig.load()
            if let uid = config.realDeviceUID, let id = findDeviceByUID(uid) {
                setDefaultOutputDevice(id)
            }
            // Clean up aggregate devices by UID
            if let agg = findDeviceByUID("eq-aggregate-device") {
                destroyAggregate(agg)
            }
            unlink(EQConfig.socketPath)
            exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }

    // MARK: - IPC Server

    func startIPCServer() {
        unlink(EQConfig.socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { fputs("eq: failed to create socket\n", stderr); return }

        var serverAddr = sockaddr_un()
        serverAddr.sun_family = sa_family_t(AF_UNIX)
        let path = EQConfig.socketPath
        let maxLen = MemoryLayout.size(ofValue: serverAddr.sun_path)
        path.withCString { cstr in
            withUnsafeMutablePointer(to: &serverAddr.sun_path) { ptr in
                _ = memcpy(ptr, cstr, min(maxLen, path.utf8.count))
            }
        }

        let bindResult = withUnsafePointer(to: &serverAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                bind(fd, addr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { fputs("eq: bind failed\n", stderr); close(fd); return }

        listen(fd, 5)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let clientFD = accept(fd, nil, nil)
                guard clientFD >= 0, let self = self else { continue }

                var buffer = [UInt8](repeating: 0, count: 1024)
                let bytesRead = read(clientFD, &buffer, buffer.count - 1)
                guard bytesRead > 0 else { close(clientFD); continue }

                let command = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let response: String
                if command == "status" {
                    response = DispatchQueue.main.sync { self.statusJSON() }
                } else {
                    response = DispatchQueue.main.sync { self.handleCommand(command) }
                }

                let responseData = (response + "\n").data(using: .utf8)!
                responseData.withUnsafeBytes { ptr in
                    _ = write(clientFD, ptr.baseAddress!, responseData.count)
                }
                close(clientFD)
            }
        }
    }

    func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func statusJSON() -> String {
        let deviceName = jsonEscape(getDeviceName(realDeviceID))
        let transport = transportName(getDeviceTransportType(realDeviceID))
        let active = engine.isRunning
        return """
        {"enabled":\(config.enabled),"active":\(active),"device":"\(deviceName)","transport":"\(transport)","bass":\(config.bass),"mid":\(config.mid),"treble":\(config.treble)}
        """
    }

    func handleCommand(_ cmd: String) -> String {
        let parts = cmd.split(separator: " ", maxSplits: 1)
        let action = String(parts[0])
        let arg = parts.count > 1 ? String(parts[1]) : nil

        switch action {
        case "on":
            config.enabled = true
            config.save()
            if isEQEligible(realDeviceID) { activate() }
            return statusJSON()
        case "off":
            config.enabled = false
            config.save()
            deactivate()
            return statusJSON()
        case "toggle":
            config.enabled = !config.enabled
            config.save()
            if config.enabled && isEQEligible(realDeviceID) { activate() } else { deactivate() }
            return statusJSON()
        case "bass":
            if let v = arg.flatMap(Float.init) { config.bass = max(-24, min(24, v)); config.save(); engine.config = config; engine.updateEQ() }
            return statusJSON()
        case "mid":
            if let v = arg.flatMap(Float.init) { config.mid = max(-24, min(24, v)); config.save(); engine.config = config; engine.updateEQ() }
            return statusJSON()
        case "treble":
            if let v = arg.flatMap(Float.init) { config.treble = max(-24, min(24, v)); config.save(); engine.config = config; engine.updateEQ() }
            return statusJSON()
        case "devices":
            let devs = getAllOutputDevices().filter { !isVirtualDevice($0.transport) }
            let items = devs.map { "{\"name\":\"\(jsonEscape($0.name))\",\"transport\":\"\(transportName($0.transport))\",\"eligible\":\(isEQEligible($0.id))}" }
            return "[\(items.joined(separator: ","))]"
        default:
            return "{\"error\":\"unknown command: \(action)\"}"
        }
    }
}

// MARK: - IPC Client

func sendToSocket(_ message: String) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = EQConfig.socketPath
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    path.withCString { cstr in
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            _ = memcpy(ptr, cstr, min(maxLen, path.utf8.count))
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
            connect(fd, addr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else { return nil }

    let data = (message + "\n").data(using: .utf8)!
    data.withUnsafeBytes { ptr in
        _ = write(fd, ptr.baseAddress!, data.count)
    }

    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = read(fd, &buffer, buffer.count - 1)
    guard bytesRead > 0 else { return nil }
    return String(bytes: buffer[0..<bytesRead], encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - CLI Output

func printStatus(_ json: String) {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print(json)
        return
    }

    if let error = obj["error"] as? String {
        fputs("eq: \(error)\n", stderr)
        return
    }

    let enabled = obj["enabled"] as? Bool ?? false
    let active = obj["active"] as? Bool ?? false
    let device = obj["device"] as? String ?? "?"
    let transport = obj["transport"] as? String ?? "?"
    let bass = obj["bass"] as? Double ?? 0
    let mid = obj["mid"] as? Double ?? 0
    let treble = obj["treble"] as? Double ?? 0

    let state: String
    if active { state = "ON" }
    else if enabled { state = "STANDBY" }
    else { state = "OFF" }

    print("EQ: \(state) | \(device) (\(transport))")
    print("Bass: \(String(format: "%+.1f", bass))dB  Mid: \(String(format: "%+.1f", mid))dB  Treble: \(String(format: "%+.1f", treble))dB")
}

func printDevices(_ json: String) {
    guard let data = json.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        print(json)
        return
    }
    for dev in arr {
        let name = dev["name"] as? String ?? "?"
        let transport = dev["transport"] as? String ?? "?"
        let eligible = dev["eligible"] as? Bool ?? false
        print("  \(eligible ? "*" : " ") \(name) (\(transport))")
    }
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args[0] == "status" {
    if let response = sendToSocket("status") {
        printStatus(response)
    } else {
        print("EQ: daemon not running")
    }
} else if args[0] == "daemon" {
    EQDaemon().start()
} else if args[0] == "devices" {
    if let response = sendToSocket("devices") {
        printDevices(response)
    } else {
        print("EQ: daemon not running")
    }
} else if ["on", "off", "toggle"].contains(args[0]) {
    if let response = sendToSocket(args[0]) {
        printStatus(response)
    } else {
        print("EQ: daemon not running")
    }
} else if ["bass", "mid", "treble"].contains(args[0]) {
    guard args.count > 1, let _ = Float(args[1]) else {
        fputs("usage: eq \(args[0]) <dB>\n", stderr)
        exit(1)
    }
    if let response = sendToSocket("\(args[0]) \(args[1])") {
        printStatus(response)
    } else {
        print("EQ: daemon not running")
    }
} else {
    print("""
    usage: eq [command]
      eq              show status
      eq daemon       run as daemon
      eq on/off       enable/disable
      eq toggle       toggle on/off
      eq bass <dB>    set bass (-24 to +24)
      eq mid <dB>     set mid
      eq treble <dB>  set treble
      eq devices      list audio devices
    """)
}
