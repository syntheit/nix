import SwiftUI

// MARK: - Color theme (Tokyo Night inspired)

extension Color {
    static let accent = Color(red: 0.48, green: 0.63, blue: 0.97)     // #7aa2f7
    static let green = Color(red: 0.45, green: 0.81, blue: 0.56)      // #73d98e
    static let yellow = Color(red: 0.89, green: 0.79, blue: 0.46)     // #e3c975
    static let red = Color(red: 0.94, green: 0.42, blue: 0.42)        // #f06b6b
    static let subtle = Color.white.opacity(0.5)
    static let dimmed = Color.white.opacity(0.3)
    // Gauge colors — distinct, consistent, Tokyo Night palette
    static let gaugeCyan = Color(red: 0.49, green: 0.81, blue: 1.0)   // #7dcfff
    static let gaugePurple = Color(red: 0.73, green: 0.60, blue: 0.97) // #bb9af7
    static let gaugeTeal = Color(red: 0.45, green: 0.84, blue: 0.76)  // #73d6c1
}

// MARK: - Main Dashboard View

struct DashboardView: View {
    // Mach/IOKit calls are <1ms — safe to init synchronously
    @State private var cpu = SystemBridge.getCPU()
    @State private var memory = SystemBridge.getMemory()
    @State private var temp = SystemBridge.getTemp()
    @State private var battery = SystemBridge.getBattery()
    @State private var time = Date()
    @State private var privacyMode = SystemBridge.isPrivacyMode()
    @State private var uptime = SystemBridge.getUptime()
    @State private var diskFree = SystemBridge.getDiskFree()
    @State private var network = SystemBridge.getNetwork()
    @State private var claudeUsage = ClaudeUsage.Snapshot.zero

    // Volume via CoreAudio is instant (<1ms), Spotify needs AppleScript cache
    @State private var volume = SystemBridge.getVolume()
    @State private var spotify = SystemBridge.getCachedSpotify()

    // Slow data loaded from cache synchronously (instant if cached, empty if not)
    private static let foyerServers: [AsyncData.FoyerConfig] = [
        AsyncData.FoyerConfig(name: "harbor", url: "https://harbor.matv.io"),
        AsyncData.FoyerConfig(name: "raven", url: "https://raven.matv.io"),
        AsyncData.FoyerConfig(name: "conduit", url: "https://conduit.matv.io"),
    ]

    @State private var weather = AsyncData.getCachedWeather()
    @State private var exchange = AsyncData.getCachedExchange()
    @State private var servers = AsyncData.getCachedServers(foyerServers.map(\.name))
    @State private var agenda = AsyncData.getCachedCalendar()

    // Tracks whether initial render is done (suppresses entry animations)
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.clear
            AuroraView()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                clockSection
                systemInfoRow
                    .padding(.top, 28)
                if spotify.state != "off" {
                    mediaSection
                        .frame(height: 20)
                        .clipped()
                        .padding(.top, 20)
                }
                if !agenda.isEmpty {
                    agendaSection
                        .padding(.top, 24)
                }
                systemsSection
                    .padding(.top, 24)
                if !exchange.isEmpty {
                    exchangeSection
                        .padding(.top, 24)
                }
                if let w = weather {
                    weatherSection(w)
                        .padding(.top, 24)
                }
            }
            .padding(48)
            .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(appeared ? .easeInOut(duration: 0.3) : nil, value: servers.count)
        .animation(appeared ? .easeInOut(duration: 0.3) : nil, value: exchange.count)
        .animation(appeared ? .easeInOut(duration: 0.3) : nil, value: weather?.location)
        .task(id: "clock") {
            while !Task.isCancelled {
                time = Date()
                privacyMode = SystemBridge.isPrivacyMode()
                network = SystemBridge.getNetwork()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: "fast") {
            refreshFast()
            appeared = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                refreshFast()
            }
        }
        .task(id: "servers") {
            while !Task.isCancelled {
                let fresh = await AsyncData.getServers(foyerServers: Self.foyerServers, useCache: false)
                if !fresh.isEmpty { servers = fresh }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: "slow") {
            async let w = AsyncData.getWeather()
            async let e = AsyncData.getExchange()
            async let c = AsyncData.getTodayEvents()
            let newWeather = await w
            let newExchange = await e
            let newAgenda = await c
            if let nw = newWeather { weather = nw }
            if !newExchange.isEmpty { exchange = newExchange }
            if !newAgenda.isEmpty { agenda = newAgenda }
        }
        .task(id: "claude") {
            while !Task.isCancelled {
                let snapshot = await Task.detached(priority: .utility) {
                    ClaudeUsage.read()
                }.value
                if snapshot != claudeUsage { claudeUsage = snapshot }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func refreshFast() {
        cpu = SystemBridge.getCPU()
        memory = SystemBridge.getMemory()
        temp = SystemBridge.getTemp()
        battery = SystemBridge.getBattery()
        volume = SystemBridge.getVolume()
        spotify = SystemBridge.getSpotify()
        uptime = SystemBridge.getUptime()
        diskFree = SystemBridge.getDiskFree()
    }

    // MARK: - Sections

    // World clock cities — skip any matching local timezone
    private static let worldClocks: [(label: String, tz: String)] = [
        ("BA", "America/Argentina/Buenos_Aires"),
        ("NYC", "America/New_York"),
        ("CHI", "America/Chicago"),
    ]

    private var clockSection: some View {
        VStack(spacing: 4) {
            Text(time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(.system(size: 56, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(.white)
            Text(time, format: .dateTime.weekday(.wide).month(.wide).day(.defaultDigits).year())
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color.subtle)
            worldClockRow
                .padding(.top, 6)
        }
    }

    private static let worldClockFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var worldClockRow: some View {
        let local = TimeZone.current.identifier
        let clocks = Self.worldClocks.filter { $0.tz != local }.compactMap { city -> (String, String)? in
            guard let tz = TimeZone(identifier: city.tz) else { return nil }
            Self.worldClockFmt.timeZone = tz
            return (city.label, Self.worldClockFmt.string(from: time))
        }
        return HStack(spacing: 16) {
            ForEach(clocks, id: \.0) { city, t in
                HStack(spacing: 4) {
                    Text(city)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dimmed)
                    Text(t)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.subtle)
                }
            }
        }
    }

    private var systemInfoRow: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dimmed)
                Text(uptime)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.subtle)
            }
            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dimmed)
                Text(diskFree)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.subtle)
            }
            if let b = battery {
                HStack(spacing: 5) {
                    Image(systemName: batteryIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(b.charging ? Color.yellow : batteryColor)
                    Text("\(b.percent)%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.subtle)
                    if b.charging {
                        Text("charging")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dimmed)
                    } else if let mins = b.timeRemaining {
                        let h = mins / 60, m = mins % 60
                        Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.dimmed)
                    }
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.dimmed)
                Text("\(claudeUsage.blockPercent)% / \(claudeUsage.weeklyPercent)%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.subtle)
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.dimmed)
                Text(formatRate(network.bytesIn))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.subtle)
                Image(systemName: "arrow.up")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.dimmed)
                Text(formatRate(network.bytesOut))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.subtle)
            }
            Spacer()
            privacyIndicator
        }
        .frame(height: 24)
    }

    private var privacyIndicator: some View {
        Button(action: {
            privacyMode.toggle()
            DispatchQueue.global().async { SystemBridge.togglePrivacy() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: privacyMode ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11))
                Image(systemName: privacyMode ? "video.slash.fill" : "video.fill")
                    .font(.system(size: 11))
            }
            .foregroundStyle(privacyMode ? Color.green : Color.red)
            .frame(width: 40, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mediaSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                SystemBridge.toggleSpotify()
                if spotify.state == "playing" { spotify.state = "paused" }
                else if spotify.state == "paused" { spotify.state = "playing" }
            }) {
                Image(systemName: spotify.state == "playing" ? "play.fill" : "pause.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.green)
            }
            .buttonStyle(.plain)
            HStack(spacing: 4) {
                Text(spotify.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                Text("— \(spotify.artist)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.subtle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            volumeIndicator
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var volumeIndicator: some View {
        Button(action: {
            volume.muted.toggle()
            SystemBridge.setMuted(volume.muted)
        }) {
            HStack(spacing: 6) {
                Image(systemName: volume.muted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.subtle)
                if !volume.muted {
                    Text("\(volume.level)%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.subtle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var volumeIcon: String {
        if volume.level == 0 { return "speaker.fill" }
        if volume.level < 33 { return "speaker.wave.1.fill" }
        if volume.level < 66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var batteryIcon: String {
        guard let b = battery else { return "battery.100percent" }
        let level: String
        if b.percent > 87 { level = "100" }
        else if b.percent > 62 { level = "75" }
        else if b.percent > 37 { level = "50" }
        else if b.percent > 12 { level = "25" }
        else { level = "0" }
        return b.charging ? "battery.\(level)percent.bolt" : "battery.\(level)percent"
    }

    private var batteryColor: Color {
        guard let b = battery else { return .white }
        if b.percent > 50 { return .green }
        if b.percent > 20 { return .yellow }
        return .red
    }

    private var agendaSection: some View {
        let firstTimedIndex = agenda.firstIndex { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Today")
            ForEach(Array(agenda.enumerated()), id: \.element.id) { index, event in
                HStack(spacing: 10) {
                    if !event.isAllDay {
                        Text(event.time)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.subtle)
                    }
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    if event.isAllDay {
                        Text("today")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accent)
                    } else if index == firstTimedIndex {
                        let mins = Int(event.startDate.timeIntervalSince(time) / 60)
                        let relative: String = {
                            if mins <= 0 { return "now" }
                            if mins < 60 { return "in \(mins)m" }
                            let h = mins / 60, m = mins % 60
                            return m > 0 ? "in \(h)h \(m)m" : "in \(h)h"
                        }()
                        Text(relative)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(mins <= 15 ? Color.yellow : Color.accent)
                    }
                }
            }
        }
    }

    private var allSystems: [AsyncData.ServerHealth] {
        let local = AsyncData.ServerHealth(
            name: "swift", ok: true,
            cpuPercent: cpu, ramPercent: memory.ramPercent, memPressure: memory.pressurePercent,
            cpuTemp: temp, uptimeSecs: Int(ProcessInfo.processInfo.systemUptime)
        )
        return [local] + servers
    }

    private func formatRate(_ bytesPerSec: Int64) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", Double(bytesPerSec) / 1_048_576)
        }
        return "\(bytesPerSec / 1024)K"
    }

    private func formatUptime(_ secs: Int) -> String {
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        if d > 0 { return "\(d)d" }
        return "\(h)h"
    }

    private var systemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Systems")
            ForEach(allSystems) { server in
                HStack(spacing: 10) {
                    if !server.ok {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                    }
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 60, alignment: .leading)
                    if let cpu = server.cpuPercent, let ram = server.ramPercent {
                        MiniBar(value: cpu, color: .gaugeCyan, label: "CPU")
                        MiniBar(value: ram, color: .gaugePurple, label: "RAM",
                               overlay: server.memPressure ?? 0)
                        if let temp = server.cpuTemp, temp > 0 {
                            Text("\(temp)°")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(temp >= 80 ? Color.red : Color.subtle)
                        }
                        if let secs = server.uptimeSecs {
                            Text(formatUptime(secs))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.dimmed)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var exchangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Exchange")
            HStack(spacing: 24) {
                ForEach(exchange, id: \.label) { rate in
                    VStack(alignment: .center, spacing: 3) {
                        Text(rate.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.subtle)
                        if rate.sell.isEmpty {
                            Text(rate.buy)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(rate.buy) / \(rate.sell)")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    private func weatherSection(_ w: AsyncData.WeatherInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Weather")
            HStack(spacing: 12) {
                Text(w.location.capitalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(w.condition)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.subtle)
                Text(w.temp)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            if w.sunrise != nil || w.sunset != nil {
                HStack(spacing: 16) {
                    if let sr = w.sunrise {
                        HStack(spacing: 4) {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.yellow)
                            Text(sr)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.subtle)
                        }
                    }
                    if let ss = w.sunset {
                        HStack(spacing: 4) {
                            Image(systemName: "sunset.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.yellow)
                            Text(ss)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.subtle)
                        }
                    }
                    if let ctx = sunContext(w) {
                        Text(ctx)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dimmed)
                    }
                }
            }
        }
    }

    /// Contextual sun info: "rises in Xh", "sets in Xh Ym", or "Xh Ym daylight"
    private func sunContext(_ w: AsyncData.WeatherInfo) -> String? {
        guard let sr = w.sunrise, let ss = w.sunset else { return nil }
        let srParts = sr.split(separator: ":"), ssParts = ss.split(separator: ":")
        guard srParts.count == 2, ssParts.count == 2,
              let srH = Int(srParts[0]), let srM = Int(srParts[1]),
              let ssH = Int(ssParts[0]), let ssM = Int(ssParts[1]) else { return nil }
        let cal = Foundation.Calendar.current
        let nowH = cal.component(.hour, from: time)
        let nowM = cal.component(.minute, from: time)
        let now = nowH * 60 + nowM
        let rise = srH * 60 + srM
        let set = ssH * 60 + ssM
        if now < rise {
            let d = rise - now
            return d < 60 ? "rises in \(d)m" : "rises in \(d / 60)h \(d % 60)m"
        }
        if now < set {
            let d = set - now
            return d < 60 ? "sets in \(d)m" : "sets in \(d / 60)h \(d % 60)m"
        }
        let daylight = set - rise
        guard daylight > 0 else { return nil }
        return "\(daylight / 60)h \(daylight % 60)m daylight"
    }
}

// MARK: - Components

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.dimmed)
                .tracking(1.5)
            Rectangle()
                .fill(Color.dimmed)
                .frame(height: 0.5)
        }
    }
}

struct MiniBar: View {
    let value: Int
    let color: Color
    var label: String = ""
    var overlay: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.dimmed)
                .frame(width: 24, alignment: .trailing)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 6)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 48 * CGFloat(min(value, 100)) / 100, height: 6)
                if overlay > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 1.0, opacity: 0.2))
                        .frame(width: 48 * CGFloat(min(overlay, 100)) / 100, height: 6)
                }
            }
            Text("\(value)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.subtle)
                .frame(width: 30, alignment: .leading)
        }
    }
}

