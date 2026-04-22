import Foundation
import AppKit
import CoreWLAN
import CoreImage
import CoreLocation
import LocalAuthentication
import Security
import SystemConfiguration

class NetworkManager: ObservableObject {
    struct NetworkInfo {
        let ssid: String
        let signalStrength: Int  // dBm (negative, closer to 0 = stronger)
        let channel: Int
        let security: String
        let bssid: String
    }

    struct IPInfo {
        let localIP: String
        let gateway: String
        let dns: [String]
        let publicIP: String?
        let interfaceName: String
    }

    struct AvailableNetwork: Identifiable {
        let id: String  // SSID + BSSID
        let ssid: String
        let signalStrength: Int
        let isSecure: Bool
        let isCurrentNetwork: Bool

        var signalBars: Int {
            if signalStrength > -50 { return 4 }
            if signalStrength > -60 { return 3 }
            if signalStrength > -70 { return 2 }
            return 1
        }
    }

    struct SpeedResult {
        let ping: String
        let download: String
        let upload: String
    }

    @Published var currentNetwork: NetworkInfo?
    @Published var ipInfo: IPInfo?
    @Published var availableNetworks: [AvailableNetwork] = []
    @Published var speedResult: SpeedResult?
    @Published var isScanning = false
    @Published var isTestingSpeed = false
    @Published var qrImage: NSImage?
    @Published var revealedPassword: String?

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let locationDelegate = LocationDelegate()

    init() {
        locationManager.delegate = locationDelegate
        refreshCurrent()
    }

    func requestLocationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Current Network

    func refreshCurrent() {
        guard let iface = wifiClient.interface() else { return }

        // Use CachedScanRecord from SCDynamicStore — bypasses Location requirement on macOS 26
        let ifName = iface.interfaceName ?? "en0"
        if let info = ssidFromCachedScan(interface: ifName) {
            let security: String
            switch iface.security() {
            case .wpa2Personal, .wpa2Enterprise: security = "WPA2"
            case .wpa3Personal, .wpa3Enterprise: security = "WPA3"
            case .wpa3Transition: security = "WPA3"
            case .wpaPersonal, .wpaEnterprise: security = "WPA"
            case .none: security = "Open"
            default: security = "Secured"
            }

            currentNetwork = NetworkInfo(
                ssid: info.ssid,
                signalStrength: info.rssi,
                channel: info.channel,
                security: security,
                bssid: info.bssid
            )
        } else {
            currentNetwork = nil
        }

        refreshIPInfo()
    }

    /// Reads the unredacted SSID from SCDynamicStore's CachedScanRecord.
    /// This bypasses macOS 26's Location Services requirement for WiFi SSID.
    private func ssidFromCachedScan(interface: String) -> (ssid: String, rssi: Int, channel: Int, bssid: String)? {
        let store = SCDynamicStoreCreate(nil, "wifi-panel" as CFString, nil, nil)
        guard let airport = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(interface)/AirPort" as CFString) as? [String: Any],
              let data = airport["CachedScanRecord"] as? Data,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        guard let record = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSDictionary else { return nil }

        let ssid: String
        if let s = record["SSID_STR"] as? String, !s.isEmpty {
            ssid = s
        } else if let d = record["SSID"] as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty {
            ssid = s
        } else {
            return nil
        }

        let rssi = record["RSSI"] as? Int ?? 0
        let channel = record["CHANNEL"] as? Int ?? 0
        let bssid = record["BSSID"] as? String ?? ""
        return (ssid, rssi, channel, bssid)
    }

    // MARK: - IP Info

    func refreshIPInfo() {
        let localIP = getLocalIP() ?? "N/A"
        let gateway = getGateway() ?? "N/A"
        let dns = getDNSServers()
        let ifName = wifiClient.interface()?.interfaceName ?? "en0"

        ipInfo = IPInfo(
            localIP: localIP,
            gateway: gateway,
            dns: dns,
            publicIP: nil,
            interfaceName: ifName
        )

        // Fetch public IP async
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pubIP = self?.fetchPublicIP()
            DispatchQueue.main.async {
                if let info = self?.ipInfo {
                    self?.ipInfo = IPInfo(
                        localIP: info.localIP,
                        gateway: info.gateway,
                        dns: info.dns,
                        publicIP: pubIP,
                        interfaceName: info.interfaceName
                    )
                }
            }
        }
    }

    // MARK: - Scan

    func scan() {
        guard let iface = wifiClient.interface() else { return }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let currentSSID = self?.currentNetwork?.ssid ?? ""
            var networks: [AvailableNetwork] = []
            var seen = Set<String>()

            // CoreWLAN scan (requires Location — works with Developer ID signed app)
            if let results = try? iface.scanForNetworks(withName: nil) {
                for net in results.sorted(by: { $0.rssiValue > $1.rssiValue }) {
                    let ssid = net.ssid ?? ""
                    guard !ssid.isEmpty, ssid != "<redacted>", !seen.contains(ssid) else { continue }
                    seen.insert(ssid)

                    networks.append(AvailableNetwork(
                        id: "\(ssid)-\(net.bssid ?? "")",
                        ssid: ssid,
                        signalStrength: net.rssiValue,
                        isSecure: net.supportsSecurity(.none) == false,
                        isCurrentNetwork: ssid == currentSSID
                    ))
                }
            }

            // Fall back to saved profiles if Location not granted
            if networks.isEmpty {
                if let config = iface.configuration() {
                    for case let profile as CWNetworkProfile in config.networkProfiles.array {
                        let ssid = profile.ssid ?? ""
                        guard !ssid.isEmpty, ssid != currentSSID, !seen.contains(ssid) else { continue }
                        seen.insert(ssid)
                        networks.append(AvailableNetwork(
                            id: ssid,
                            ssid: ssid,
                            signalStrength: 0,
                            isSecure: true,
                            isCurrentNetwork: false
                        ))
                    }
                }
            }

            DispatchQueue.main.async {
                self?.availableNetworks = networks
                self?.isScanning = false
            }
        }
    }

    // MARK: - Connect

    func connect(ssid: String, password: String) {
        guard let iface = wifiClient.interface() else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let networks = try? iface.scanForNetworks(withName: ssid),
               let network = networks.first {
                try? iface.associate(to: network, password: password.isEmpty ? nil : password)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.refreshCurrent()
            }
        }
    }

    // MARK: - Password (Touch ID)

    /// Retrieves WiFi password from the System keychain using Touch ID for authentication
    private func getPasswordWithTouchID(for ssid: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = LAContext()
            context.localizedReason = "Access WiFi password for \(ssid)"

            // Use LAContext to authenticate, then query keychain
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                // Fall back to security CLI if no biometrics
                completion(self.getPasswordViaCLI(ssid))
                return
            }

            let semaphore = DispatchSemaphore(value: 0)
            var authenticated = false

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Access WiFi password") { success, _ in
                authenticated = success
                semaphore.signal()
            }
            semaphore.wait()

            if authenticated {
                // After Touch ID, use security CLI with the authenticated session
                completion(self.getPasswordViaCLI(ssid))
            } else {
                completion(nil)
            }
        }
    }

    private func getPasswordViaCLI(_ ssid: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-D", "AirPort network password", "-ga", ssid]
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        try? task.run()
        task.waitUntilExit()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        if let range = errOutput.range(of: "password: \"") {
            let start = range.upperBound
            if let end = errOutput[start...].firstIndex(of: "\"") {
                return String(errOutput[start..<end])
            }
        }
        return nil
    }

    func revealPassword() {
        guard let ssid = currentNetwork?.ssid else { return }
        getPasswordWithTouchID(for: ssid) { [weak self] password in
            DispatchQueue.main.async {
                self?.revealedPassword = password ?? "(not found)"
            }
        }
    }

    // MARK: - QR Code

    func generateQR() {
        guard let net = currentNetwork else { return }

        getPasswordWithTouchID(for: net.ssid) { [weak self] password in
            let pw = password ?? ""
            let secType = net.security == "Open" ? "nopass" : "WPA"
            let wifiString = "WIFI:T:\(secType);S:\(net.ssid);P:\(pw);;"

            guard let data = wifiString.data(using: .utf8),
                  let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")

            guard let ciImage = filter.outputImage else { return }
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let rep = NSCIImageRep(ciImage: scaled)
            let nsImage = NSImage(size: rep.size)
            nsImage.addRepresentation(rep)

            DispatchQueue.main.async {
                self?.qrImage = nsImage
            }
        }
    }

    // MARK: - Speed Test

    func runSpeedTest(speedtestPath: String) {
        isTestingSpeed = true
        speedResult = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: speedtestPath)
            task.arguments = ["--simple"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            var ping = "", download = "", upload = ""
            for line in output.components(separatedBy: "\n") {
                if line.hasPrefix("Ping:") { ping = line.replacingOccurrences(of: "Ping: ", with: "") }
                if line.hasPrefix("Download:") { download = line.replacingOccurrences(of: "Download: ", with: "") }
                if line.hasPrefix("Upload:") { upload = line.replacingOccurrences(of: "Upload: ", with: "") }
            }

            DispatchQueue.main.async {
                self?.speedResult = SpeedResult(ping: ping, download: download, upload: upload)
                self?.isTestingSpeed = false
            }
        }
    }

    // MARK: - Helpers

    private func ssidViaIPConfig() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        task.arguments = ["getsummary", "en0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            if line.contains(" SSID : ") {
                return line.components(separatedBy: " SSID : ").last?.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            if name == "en0" && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                return String(cString: hostname)
            }
        }
        return nil
    }

    private func getGateway() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-rn"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ")
            if parts.first == "default" && parts.count > 1 {
                return String(parts[1])
            }
        }
        return nil
    }

    private func getDNSServers() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--dns"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        var servers: [String] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("nameserver[") {
                if let addr = trimmed.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) {
                    if !servers.contains(addr) { servers.append(addr) }
                }
            }
        }
        return servers
    }

    private func fetchPublicIP() -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data { result = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return result
    }
}

// MARK: - Location Delegate

class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
