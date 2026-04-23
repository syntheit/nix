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

    private static func readCache(_ name: String) -> String? {
        let path = "\(cacheDir)/\(name)"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < cacheTTL
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
    }

    static func getWeather() async -> WeatherInfo? {
        if let cached = readCache("weather") {
            return parseWeather(cached)
        }
        guard let url = URL(string: "https://wttr.in/?m&format=%l|%C|%t") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("curl", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        writeCache("weather", text)
        return parseWeather(text)
    }

    private static func parseWeather(_ raw: String) -> WeatherInfo? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count >= 3 else { return nil }
        var tempStr = String(parts[2]).trimmingCharacters(in: .whitespaces)
        if tempStr.hasPrefix("+") { tempStr = String(tempStr.dropFirst()) }
        // Strip trailing country code (e.g. ", United States" or ", Us")
        var location = String(parts[0]).trimmingCharacters(in: .whitespaces)
        if let range = location.range(of: #",\s*\w{2}$"#, options: .regularExpression) {
            location = String(location[..<range.lowerBound])
        }
        return WeatherInfo(
            location: location,
            condition: String(parts[1]).trimmingCharacters(in: .whitespaces),
            temp: tempStr
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
        var info: String   // Summary line for display
        var ok: Bool
        // Structured fields (populated by Foyer API, nil for SSH-only servers)
        var cpuPercent: Int?
        var ramPercent: Int?
        var memPressure: Int?  // compressed memory as % of total RAM
        var cpuTemp: Int?
        var containers: Int?
    }

    struct FoyerConfig {
        var name: String   // Display name (e.g. "harbor")
        var url: String    // Foyer API base URL
    }

    static func getServers(
        sshServers: [String],
        healthScript: String,
        foyerServers: [FoyerConfig]
    ) async -> [ServerHealth] {
        // Check cache first
        let allNames = foyerServers.map(\.name) + sshServers
        if let cached = readCachedServers(allNames), !cached.isEmpty {
            return cached
        }

        return await withTaskGroup(of: ServerHealth.self) { group in
            for cfg in foyerServers {
                group.addTask { await fetchFoyerServer(cfg) }
            }
            for name in sshServers {
                group.addTask { await fetchSSHServer(name, script: healthScript) }
            }
            var results: [ServerHealth] = []
            for await result in group { results.append(result) }
            return allNames.compactMap { n in results.first { $0.name == n } }
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
        // foyer-api reads ~/.ssh/id_ed25519 (or mainkey) and signs the request
        let cmd = "foyer-api --host \(cfg.url) /api/health"
        guard let output = shell(cmd, timeout: 10),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ServerHealth(name: cfg.name, info: "unreachable", ok: false)
        }

        // Parse structured fields
        let cpu = (json["cpu"] as? [String: Any])?["usage_percent"] as? Double ?? 0
        let mem = (json["memory"] as? [String: Any])?["usage_percent"] as? Double ?? 0
        let sys = json["system"] as? [String: Any]
        let uptimeSec = sys?["uptime_seconds"] as? Double ?? 0
        let load = (sys?["load_avg"] as? [Double])?.first ?? 0
        let temps = json["temperatures"] as? [String: Any]
        let cpuTemp = temps?["cpu"] as? Int ?? 0
        let containers = ((json["docker"] as? [String: Any])?["containers"] as? [[String: Any]])?
            .filter { ($0["state"] as? String) == "running" }.count ?? 0

        let days = Int(uptimeSec) / 86400
        let info = "\(days)d  cpu \(Int(cpu))%  ram \(Int(mem))%  \(cpuTemp)°  load \(String(format: "%.1f", load))  containers \(containers)"

        // Cache as structured format: foyer|cpu|ram|uptime|load|containers|cpuTemp
        let cacheStr = "foyer|\(Int(cpu))|\(Int(mem))|\(Int(uptimeSec))|\(String(format: "%.2f", load))|\(containers)|\(cpuTemp)"
        writeCache("server_\(cfg.name)", cacheStr)

        return ServerHealth(
            name: cfg.name, info: info, ok: true,
            cpuPercent: Int(cpu), ramPercent: Int(mem), cpuTemp: cpuTemp, containers: containers
        )
    }

    // MARK: SSH fetch (unchanged, for raven)

    private static func fetchSSHServer(_ name: String, script: String) async -> ServerHealth {
        let cmd = "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \(name) bash -c '\(script)'"
        guard let output = shell(cmd, timeout: 8) else {
            return ServerHealth(name: name, info: "unreachable", ok: false)
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        writeCache("server_\(name)", trimmed)
        return ServerHealth(name: name, info: trimmed, ok: !trimmed.isEmpty)
    }

    // MARK: Cache parsing

    private static func parseServerCache(name: String, raw: String) -> ServerHealth {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Detect foyer-format cache: "foyer|cpu|ram|uptime|load|containers|cpuTemp"
        if trimmed.hasPrefix("foyer|") {
            let parts = trimmed.split(separator: "|")
            if parts.count >= 6 {
                let cpu = Int(parts[1]) ?? 0
                let ram = Int(parts[2]) ?? 0
                let uptimeSec = Int(parts[3]) ?? 0
                let load = parts[4]
                let ct = Int(parts[5]) ?? 0
                let temp = parts.count >= 7 ? Int(parts[6]) ?? 0 : 0
                let days = uptimeSec / 86400
                let info = "\(days)d  cpu \(cpu)%  ram \(ram)%  \(temp)°  load \(load)  containers \(ct)"
                return ServerHealth(name: name, info: info, ok: true, cpuPercent: cpu, ramPercent: ram, cpuTemp: temp, containers: ct)
            }
        }
        // SSH-format cache: plain text
        return ServerHealth(name: name, info: trimmed, ok: !trimmed.isEmpty)
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
        let path = "\(cacheDir)/calendar"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < calendarCacheTTL
        else { return [] }
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

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate(); return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
