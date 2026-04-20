{
  stdenv,
  writeText,
  swift,
}:

let
  src = writeText "systemstats.swift" ''
    import Foundation
    import IOKit

    // MARK: - CPU Usage via host_processor_info (delta-based)

    struct CPUTicks {
        var user: Int64; var system: Int64; var idle: Int64; var nice: Int64
        var total: Int64 { user + system + idle + nice }
        var busy: Int64 { user + system + nice }
    }

    let stateFile = "/tmp/.systemstats_cpu_ticks"

    func getCPUTicks() -> CPUTicks? {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.size))
        }

        var t = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            t.user   += Int64(info[offset + Int(CPU_STATE_USER)])
            t.system += Int64(info[offset + Int(CPU_STATE_SYSTEM)])
            t.idle   += Int64(info[offset + Int(CPU_STATE_IDLE)])
            t.nice   += Int64(info[offset + Int(CPU_STATE_NICE)])
        }
        return t
    }

    func loadPrevTicks() -> CPUTicks? {
        guard let data = try? String(contentsOfFile: stateFile, encoding: .utf8) else { return nil }
        let parts = data.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count == 4,
              let u = Int64(parts[0]), let s = Int64(parts[1]),
              let i = Int64(parts[2]), let n = Int64(parts[3]) else { return nil }
        return CPUTicks(user: u, system: s, idle: i, nice: n)
    }

    func saveTicks(_ t: CPUTicks) {
        try? "\(t.user) \(t.system) \(t.idle) \(t.nice)".write(toFile: stateFile, atomically: true, encoding: .utf8)
    }

    func getCPUUsage() -> Int? {
        guard let now = getCPUTicks() else { return nil }
        let prev = loadPrevTicks()
        saveTicks(now)

        guard let prev = prev else {
            // First run — no delta available, return since-boot average
            guard now.total > 0 else { return 0 }
            return Int(now.busy * 100 / now.total)
        }

        let dTotal = now.total - prev.total
        let dBusy = now.busy - prev.busy
        guard dTotal > 0 else { return 0 }
        return min(100, max(0, Int(dBusy * 100 / dTotal)))
    }

    // MARK: - RAM Usage via host_statistics64

    func getRAMUsage() -> Int? {
        let host = mach_host_self()
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(vm_kernel_page_size)

        let freePages = UInt64(vmStats.free_count)
        let specPages = UInt64(vmStats.speculative_count)
        let inactivePages = UInt64(vmStats.inactive_count)

        let freeBytes = (freePages + specPages + inactivePages) * pageSize
        let percentage = (totalRAM - freeBytes) * 100 / totalRAM
        return Int(percentage)
    }

    // MARK: - CPU Temperature via SMC

    struct SMCKeyData {
        struct vers_t {
            var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
            var reserved: UInt8 = 0; var release: UInt16 = 0
        }
        struct pLimitData_t {
            var version: UInt16 = 0; var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
        }
        struct keyInfo_t {
            var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
        }
        var key: UInt32 = 0
        var vers: vers_t = vers_t()
        var pLimitData: pLimitData_t = pLimitData_t()
        var keyInfo: keyInfo_t = keyInfo_t()
        var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
        var data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    func fcc(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for c in s.utf8 { r = r << 8 | UInt32(c) }
        return r
    }

    func getCPUTemperature() -> Int? {
        let svc = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        let K: UInt32 = 2
        guard IOServiceOpen(svc, mach_task_self_, K, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }

        func readKey(_ key: String) -> Double? {
            var i = SMCKeyData(); var o = SMCKeyData()
            i.key = fcc(key); i.data8 = 9
            var s = MemoryLayout<SMCKeyData>.size
            guard IOConnectCallStructMethod(conn, K, &i, s, &o, &s) == KERN_SUCCESS,
                  o.keyInfo.dataSize > 0 else { return nil }
            let t = o.keyInfo.dataType
            i.keyInfo = o.keyInfo; i.data8 = 5
            guard IOConnectCallStructMethod(conn, K, &i, s, &o, &s) == KERN_SUCCESS
            else { return nil }
            let b = o.bytes
            let ts = String(format: "%c%c%c%c",
                            (t>>24)&0xFF, (t>>16)&0xFF, (t>>8)&0xFF, t&0xFF)
            if ts == "flt " {
                return Double(Float(bitPattern:
                    UInt32(b.3)<<24 | UInt32(b.2)<<16 | UInt32(b.1)<<8 | UInt32(b.0)))
            }
            if ts == "ioft" {
                return Double(Int64(bitPattern:
                    UInt64(b.7)<<56 | UInt64(b.6)<<48 | UInt64(b.5)<<40 | UInt64(b.4)<<32 |
                    UInt64(b.3)<<24 | UInt64(b.2)<<16 | UInt64(b.1)<<8  | UInt64(b.0)
                )) / 65536.0
            }
            return nil
        }

        if let v = readKey("Tp09") ?? readKey("Tp02") {
            return Int(v.rounded())
        }
        return nil
    }

    // MARK: - Main

    let cpu = getCPUUsage() ?? -1
    let ram = getRAMUsage() ?? -1
    let temp = getCPUTemperature() ?? -1

    print("{\"cpu\":\(cpu),\"ram\":\(ram),\"temp\":\(temp)}")
  '';
in
stdenv.mkDerivation {
  pname = "systemstats";
  version = "0.1.0";
  inherit src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = "swiftc -O -o systemstats $src";
  installPhase = "mkdir -p $out/bin; cp systemstats $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
