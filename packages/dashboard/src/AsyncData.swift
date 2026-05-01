import Foundation
import EventKit

// MARK: - Async data providers (weather, exchange, server health)
// Cached to /tmp/dashboard-cache/ so repeated opens are instant.

private let cacheDir = "/tmp/dashboard-cache"
private let cacheTTL: TimeInterval = 1800 // 30 minutes

enum AsyncData {

    // MARK: - Cache helpers

    private static func ensureCacheDir() {
        try? FileManager.default.createDirectory(
            atPath: cacheDir, withIntermediateDirectories: true)
    }

    private static func readCache(_ name: String, ttl: TimeInterval = cacheTTL) -> String? {
        let path = "\(cacheDir)/\(name)"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < ttl
        else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    private static func writeCache(_ name: String, _ content: String) {
        ensureCacheDir()
        try? content.write(toFile: "\(cacheDir)/\(name)", atomically: true, encoding: .utf8)
    }

    // MARK: - Synchronous cache readers (for instant first frame)

    static func getCachedWeather() -> WeatherInfo? {
        guard let cached = readCache("weather") else { return nil }
        return parseWeather(cached)
    }

    static func getCachedExchange() -> [ExchangeRate] {
        guard let cached = readCache("exchange"), let parsed = parseExchange(cached) else { return [] }
        return parsed
    }

    // MARK: - Weather

    struct WeatherInfo {
        var location: String
        var condition: String
        var temp: String
        var sunrise: String?  // 24h format "5:42"
        var sunset: String?   // 24h format "19:15"
    }

    static func getWeather() async -> WeatherInfo? {
        if let cached = readCache("weather") {
            return parseWeather(cached)
        }
        // Use JSON API for reliable location names (%l can return coordinates)
        guard let url = URL(string: "https://wttr.in/?m&format=j1") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("curl", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let nearest = (json["nearest_area"] as? [[String: Any]])?.first
        let current = (json["current_condition"] as? [[String: Any]])?.first
        let astro = ((json["weather"] as? [[String: Any]])?.first?["astronomy"] as? [[String: Any]])?.first

        let area = (nearest?["areaName"] as? [[String: Any]])?.first?["value"] as? String ?? ""
        let region = (nearest?["region"] as? [[String: Any]])?.first?["value"] as? String ?? ""
        let location = region.isEmpty ? area : "\(area), \(region)"
        let condition = (current?["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? ""
        let tempC = current?["temp_C"] as? String ?? ""
        let sunrise = astro?["sunrise"] as? String ?? ""
        let sunset = astro?["sunset"] as? String ?? ""

        let cacheStr = "\(location)|\(condition)|\(tempC)°C|\(sunrise)|\(sunset)"
        writeCache("weather", cacheStr)
        return parseWeather(cacheStr)
    }

    /// Convert "06:15 AM" / "07:30 PM" / "06:44:45" to 24h "6:15" / "19:30" (strips seconds)
    private static func cleanTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let tokens = trimmed.components(separatedBy: " ")
        guard let timePart = tokens.first else { return trimmed }
        let components = timePart.split(separator: ":")
        guard components.count >= 2, var hour = Int(components[0]), let min = Int(components[1])
        else { return trimmed }
        if tokens.count > 1 {
            let ampm = tokens[1].uppercased()
            if ampm == "PM" && hour != 12 { hour += 12 }
            if ampm == "AM" && hour == 12 { hour = 0 }
        }
        return String(format: "%d:%02d", hour, min)
    }

    private static func parseWeather(_ raw: String) -> WeatherInfo? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        var tempStr = String(parts[2]).trimmingCharacters(in: .whitespaces)
        if tempStr.hasPrefix("+") { tempStr = String(tempStr.dropFirst()) }
        let location = String(parts[0]).trimmingCharacters(in: .whitespaces)
        var sunrise: String? = nil
        var sunset: String? = nil
        if parts.count >= 5 {
            let sr = cleanTime(String(parts[3]))
            let ss = cleanTime(String(parts[4]))
            if sr.contains(":") { sunrise = sr }
            if ss.contains(":") { sunset = ss }
        }
        return WeatherInfo(
            location: location,
            condition: String(parts[1]).trimmingCharacters(in: .whitespaces),
            temp: tempStr,
            sunrise: sunrise,
            sunset: sunset
        )
    }

    // MARK: - Exchange Rates

    struct ExchangeRate {
        var label: String
        var buy: String
        var sell: String
    }

    static func getExchange() async -> [ExchangeRate] {
        if let cached = readCache("exchange"), let parsed = parseExchange(cached) {
            return parsed
        }
        var rates: [ExchangeRate] = []

        // ARS (dolar blue, oficial, mep)
        if let url = URL(string: "https://dolarapi.com/v1/dolares"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let targets = ["blue", "oficial", "bolsa"]
            let labels = ["blue": "Blue", "oficial": "Official", "bolsa": "MEP"]
            for casa in targets {
                if let item = json.first(where: { $0["casa"] as? String == casa }),
                   let buy = item["compra"] as? Double,
                   let sell = item["venta"] as? Double {
                    let label = labels[casa] ?? casa
                    rates.append(ExchangeRate(
                        label: label,
                        buy: String(Int(buy)),
                        sell: String(Int(sell))
                    ))
                }
            }
        }

        // BRL
        if let url = URL(string: "https://raw.githubusercontent.com/syntheit/exchange-rates/refs/heads/main/rates.json"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ratesObj = json["rates"] as? [String: Any],
           let brl = ratesObj["BRL"] as? Double {
            let rounded = String(format: "%.2f", brl)
            rates.append(ExchangeRate(label: "BRL", buy: rounded, sell: ""))
        }

        // Cache the result
        let cacheStr = rates.map { "\($0.label)|\($0.buy)|\($0.sell)" }.joined(separator: "\n")
        writeCache("exchange", cacheStr)
        return rates
    }

    private static func parseExchange(_ raw: String) -> [ExchangeRate]? {
        let lines = raw.split(separator: "\n")
        guard !lines.isEmpty else { return nil }
        return lines.compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            return ExchangeRate(label: String(parts[0]), buy: String(parts[1]), sell: String(parts[2]))
        }
    }

    // MARK: - Server Health

    struct ServerHealth: Identifiable {
        var id: String { name }
        var name: String
        var ok: Bool
        var cpuPercent: Int?
        var ramPercent: Int?
        var memPressure: Int?  // compressed memory as % of total RAM
        var cpuTemp: Int?
        var uptimeSecs: Int?
    }

    struct FoyerConfig {
        var name: String   // Display name (e.g. "harbor")
        var url: String    // Foyer API base URL
    }

    static func getServers(foyerServers: [FoyerConfig], useCache: Bool = true) async -> [ServerHealth] {
        let names = foyerServers.map(\.name)
        if useCache, let cached = readCachedServers(names), !cached.isEmpty {
            return cached
        }

        return await withTaskGroup(of: ServerHealth.self) { group in
            for cfg in foyerServers {
                group.addTask { await fetchFoyerServer(cfg) }
            }
            var results: [ServerHealth] = []
            for await result in group { results.append(result) }
            return names.compactMap { n in results.first { $0.name == n } }
        }
    }

    static func getCachedServers(_ names: [String]) -> [ServerHealth] {
        var results: [ServerHealth] = []
        for name in names {
            if let cached = readCache("server_\(name)") {
                let h = parseServerCache(name: name, raw: cached)
                results.append(h)
            }
        }
        return results
    }

    private static func readCachedServers(_ names: [String]) -> [ServerHealth]? {
        var results: [ServerHealth] = []
        for name in names {
            guard let cached = readCache("server_\(name)") else { return nil }
            results.append(parseServerCache(name: name, raw: cached))
        }
        return results
    }

    // MARK: Foyer API fetch (via foyer-api binary which handles SSH key signing)

    private static func fetchFoyerServer(_ cfg: FoyerConfig) async -> ServerHealth {
        let cmd = "foyer-api --host \(cfg.url) /api/health"
        guard let output = shell(cmd, timeout: 10),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ServerHealth(name: cfg.name, ok: false)
        }

        let cpu = (json["cpu"] as? [String: Any])?["usage_percent"] as? Double ?? 0
        let memObj = json["memory"] as? [String: Any]
        let mem = memObj?["usage_percent"] as? Double ?? 0
        let cmpr = memObj?["compressed_percent"] as? Double ?? 0
        let sys = json["system"] as? [String: Any]
        let uptimeSec = sys?["uptime_seconds"] as? Double ?? 0
        let temps = json["temperatures"] as? [String: Any]
        let cpuTemp = temps?["cpu"] as? Int ?? 0

        // Cache: foyer|cpu|ram|uptime|load|containers|cpuTemp|cmpr
        let load = (sys?["load_avg"] as? [Double])?.first ?? 0
        let containers = ((json["docker"] as? [String: Any])?["containers"] as? [[String: Any]])?
            .filter { ($0["state"] as? String) == "running" }.count ?? 0
        let cacheStr = "foyer|\(Int(cpu))|\(Int(mem))|\(Int(uptimeSec))|\(String(format: "%.2f", load))|\(containers)|\(cpuTemp)|\(Int(cmpr))"
        writeCache("server_\(cfg.name)", cacheStr)

        return ServerHealth(
            name: cfg.name, ok: true,
            cpuPercent: Int(cpu), ramPercent: Int(mem), memPressure: Int(cmpr),
            cpuTemp: cpuTemp, uptimeSecs: Int(uptimeSec)
        )
    }

    // MARK: Cache parsing

    private static func parseServerCache(name: String, raw: String) -> ServerHealth {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("foyer|") else {
            return ServerHealth(name: name, ok: false)
        }
        let parts = trimmed.split(separator: "|")
        guard parts.count >= 6 else {
            return ServerHealth(name: name, ok: false)
        }
        let cpu = Int(parts[1]) ?? 0
        let ram = Int(parts[2]) ?? 0
        let uptimeSec = Int(parts[3]) ?? 0
        let temp = parts.count >= 7 ? Int(parts[6]) ?? 0 : 0
        let cmpr = parts.count >= 8 ? Int(parts[7]) ?? 0 : 0
        return ServerHealth(
            name: name, ok: true,
            cpuPercent: cpu, ramPercent: ram, memPressure: cmpr,
            cpuTemp: temp, uptimeSecs: uptimeSec
        )
    }

    // MARK: - Server Detail (full /api/health payload, fetched on demand)

    struct ServerDetail: Equatable {
        var name: String
        var ok: Bool
        var cpuPercent: Int
        var ramPercent: Int
        var memCompressed: Int?
        var cpuTemp: Int?
        var uptimeSecs: Int?
        var gpu: GPUDetail?
        var pools: [PoolDetail]
        var mounts: [MountDetail]
        var rxBytesPerSec: Int64
        var txBytesPerSec: Int64
        var dockerRunning: Int?
        var jellyfinStreams: Int?
        var minecraft: MinecraftDetail?
    }

    struct MinecraftDetail: Equatable {
        var online: Bool
        var players: Int
        var maxPlayers: Int
    }

    struct GPUDetail: Equatable {
        var name: String
        var utilPercent: Int
        var memUsedMB: Int
        var memTotalMB: Int
        var temp: Int
        var powerWatts: Double
    }

    struct PoolDetail: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var usagePercent: Int
        var totalBytes: Int64
        var usedBytes: Int64
        var health: String
    }

    struct MountDetail: Identifiable, Equatable {
        var id: String { mountpoint }
        var mountpoint: String
        var usagePercent: Int
        var totalBytes: Int64
        var usedBytes: Int64
    }

    static func getServerDetail(name: String, url: String) async -> ServerDetail {
        let task = Task.detached(priority: .utility) {
            shell("foyer-api --host \(url) /api/health", timeout: 8)
        }
        guard let output = await task.value,
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ServerDetail(
                name: name, ok: false,
                cpuPercent: 0, ramPercent: 0,
                pools: [], mounts: [],
                rxBytesPerSec: 0, txBytesPerSec: 0
            )
        }

        let cpu = (json["cpu"] as? [String: Any])?["usage_percent"] as? Double ?? 0
        let memObj = json["memory"] as? [String: Any]
        let mem = memObj?["usage_percent"] as? Double ?? 0
        let cmpr = memObj?["compressed_percent"] as? Double ?? 0
        let sys = json["system"] as? [String: Any]
        let uptime = sys?["uptime_seconds"] as? Double ?? 0
        let cpuTemp = (json["temperatures"] as? [String: Any])?["cpu"] as? Int ?? 0

        var gpu: GPUDetail?
        if let g = json["gpu"] as? [String: Any] {
            gpu = GPUDetail(
                name: g["name"] as? String ?? "GPU",
                utilPercent: Int(g["utilization_percent"] as? Double ?? 0),
                memUsedMB: Int(g["memory_used_mb"] as? UInt64 ?? 0),
                memTotalMB: Int(g["memory_total_mb"] as? UInt64 ?? 0),
                temp: g["temperature"] as? Int ?? 0,
                powerWatts: g["power_watts"] as? Double ?? 0
            )
        }

        let disk = json["disk"] as? [String: Any]
        let pools: [PoolDetail] = ((disk?["pools"] as? [[String: Any]]) ?? []).compactMap { p in
            guard let name = p["name"] as? String else { return nil }
            return PoolDetail(
                name: name,
                usagePercent: Int(p["usage_percent"] as? Double ?? 0),
                totalBytes: Int64(p["total_bytes"] as? UInt64 ?? 0),
                usedBytes: Int64(p["used_bytes"] as? UInt64 ?? 0),
                health: p["health"] as? String ?? "UNKNOWN"
            )
        }
        let mounts: [MountDetail] = ((disk?["mounts"] as? [[String: Any]]) ?? []).compactMap { m in
            guard let mp = m["mountpoint"] as? String else { return nil }
            return MountDetail(
                mountpoint: mp,
                usagePercent: Int(m["usage_percent"] as? Double ?? 0),
                totalBytes: Int64(m["total_bytes"] as? UInt64 ?? 0),
                usedBytes: Int64(m["used_bytes"] as? UInt64 ?? 0)
            )
        }

        // Pick the busiest non-loopback interface; aggregating across all
        // interfaces double-counts on hosts with bridged networking.
        let ifaces = ((json["network"] as? [String: Any])?["interfaces"] as? [[String: Any]]) ?? []
        var bestRx: Int64 = 0, bestTx: Int64 = 0
        for iface in ifaces {
            let rx = Int64(iface["rx_bytes_per_sec"] as? UInt64 ?? 0)
            let tx = Int64(iface["tx_bytes_per_sec"] as? UInt64 ?? 0)
            if rx + tx > bestRx + bestTx { bestRx = rx; bestTx = tx }
        }

        let dockerCount = ((json["docker"] as? [String: Any])?["containers"] as? [[String: Any]])?
            .filter { ($0["state"] as? String) == "running" }.count

        var jellyfinStreams: Int?
        var minecraft: MinecraftDetail?
        if let svc = json["services"] as? [String: Any] {
            if let j = svc["jellyfin"] as? [String: Any] {
                jellyfinStreams = j["active_streams"] as? Int
            }
            if let m = svc["minecraft"] as? [String: Any] {
                minecraft = MinecraftDetail(
                    online: m["online"] as? Bool ?? false,
                    players: m["players"] as? Int ?? 0,
                    maxPlayers: m["max_players"] as? Int ?? 0
                )
            }
        }

        return ServerDetail(
            name: name, ok: true,
            cpuPercent: Int(cpu), ramPercent: Int(mem), memCompressed: Int(cmpr),
            cpuTemp: cpuTemp, uptimeSecs: Int(uptime),
            gpu: gpu, pools: pools, mounts: mounts,
            rxBytesPerSec: bestRx, txBytesPerSec: bestTx,
            dockerRunning: dockerCount,
            jellyfinStreams: jellyfinStreams,
            minecraft: minecraft
        )
    }

    // MARK: - Calendar (today's agenda via EventKit — handles recurring events)

    struct CalendarEvent: Identifiable {
        var id: String { "\(title)\(Int(startDate.timeIntervalSince1970))" }
        var title: String
        var time: String     // "14:30" or "" for all-day
        var startDate: Date
        var isAllDay: Bool
    }

    private static let calendarCacheTTL: TimeInterval = 300 // 5 minutes
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    static func getCachedCalendar() -> [CalendarEvent] {
        guard let raw = readCache("calendar", ttl: calendarCacheTTL) else { return [] }
        return parseCalendarCache(raw)
    }

    static func getTodayEvents() async -> [CalendarEvent] {
        let cached = getCachedCalendar()
        if !cached.isEmpty { return cached }

        let store = EKEventStore()
        let granted: Bool = await withCheckedContinuation { cont in
            if #available(macOS 14, *) {
                store.requestFullAccessToEvents { ok, _ in cont.resume(returning: ok) }
            } else {
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { return [] }

        let cal = Foundation.Calendar.current
        let now = Date()
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let ekEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)

        let events = ekEvents.map { e in
            CalendarEvent(
                title: e.title ?? "",
                time: e.isAllDay ? "" : timeFmt.string(from: e.startDate),
                startDate: e.startDate,
                isAllDay: e.isAllDay
            )
        }

        // Cache
        let cacheStr = events.map { "\($0.title)|\($0.time)|\(Int($0.startDate.timeIntervalSince1970))|\($0.isAllDay ? "1" : "0")" }.joined(separator: "\n")
        ensureCacheDir()
        writeCache("calendar", cacheStr)
        return events
    }

    private static func parseCalendarCache(_ raw: String) -> [CalendarEvent] {
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 3, let epoch = Double(parts[2]) else { return nil }
            let date = Date(timeIntervalSince1970: epoch)
            let allDay = parts.count >= 4 && parts[3] == "1"
            return CalendarEvent(title: String(parts[0]), time: String(parts[1]), startDate: date, isAllDay: allDay)
        }
    }

    // MARK: - Shell helper

    static func shell(_ command: String, timeout: TimeInterval = 10) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let sem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
