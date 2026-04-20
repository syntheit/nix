{
  stdenv,
  writeText,
  swift,
}:

let
  src = writeText "cputemp.swift" ''
    import Foundation
    import IOKit

    struct SMCKeyData {
        struct vers_t { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct pLimitData_t { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        struct keyInfo_t { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0; var vers: vers_t = vers_t(); var pLimitData: pLimitData_t = pLimitData_t()
        var keyInfo: keyInfo_t = keyInfo_t(); var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
        var data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    let K: UInt32 = 2
    func fcc(_ s: String) -> UInt32 { var r: UInt32 = 0; for c in s.utf8 { r = r << 8 | UInt32(c) }; return r }

    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
    guard svc != 0 else { print("err"); exit(1) }
    var conn: io_connect_t = 0
    guard IOServiceOpen(svc, mach_task_self_, K, &conn) == KERN_SUCCESS else { print("err"); exit(1) }
    IOObjectRelease(svc)

    func read(_ key: String) -> Double? {
        var i = SMCKeyData(); var o = SMCKeyData()
        i.key = fcc(key); i.data8 = 9; var s = MemoryLayout<SMCKeyData>.size
        guard IOConnectCallStructMethod(conn, K, &i, s, &o, &s) == KERN_SUCCESS, o.keyInfo.dataSize > 0 else { return nil }
        let t = o.keyInfo.dataType
        i.keyInfo = o.keyInfo; i.data8 = 5
        guard IOConnectCallStructMethod(conn, K, &i, s, &o, &s) == KERN_SUCCESS else { return nil }
        let b = o.bytes
        let ts = String(format: "%c%c%c%c", (t>>24)&0xFF, (t>>16)&0xFF, (t>>8)&0xFF, t&0xFF)
        if ts == "flt " { return Double(Float(bitPattern: UInt32(b.3)<<24|UInt32(b.2)<<16|UInt32(b.1)<<8|UInt32(b.0))) }
        if ts == "ioft" { return Double(Int64(bitPattern: UInt64(b.7)<<56|UInt64(b.6)<<48|UInt64(b.5)<<40|UInt64(b.4)<<32|UInt64(b.3)<<24|UInt64(b.2)<<16|UInt64(b.1)<<8|UInt64(b.0))) / 65536.0 }
        return nil
    }

    let args = CommandLine.arguments
    if args.count > 1 && args[1] == "--all" {
        let keys = [("CPU", "Tp09"), ("CPU Max", "Tp02"), ("GPU", "TG0C"), ("SSD", "TH0T"), ("Battery", "TB0T")]
        for (name, key) in keys {
            if let v = read(key) { print("\(name): \(String(format: "%.0f", v))C") }
        }
    } else {
        if let v = read("Tp09") ?? read("Tp02") { print(String(format: "%.0f", v)) }
    }

    IOServiceClose(conn)
  '';
in
stdenv.mkDerivation {
  pname = "cputemp";
  version = "0.1.0";
  inherit src;
  nativeBuildInputs = [ swift ];
  unpackPhase = "true";
  buildPhase = "swiftc -O -o cputemp $src";
  installPhase = "mkdir -p $out/bin; cp cputemp $out/bin/";
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
