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
    @State private var ram = SystemBridge.getRAM()
    @State private var temp = SystemBridge.getTemp()
    @State private var battery = SystemBridge.getBattery()
    @State private var time = Date()
    @State private var privacyMode = SystemBridge.isPrivacyMode()
    @State private var uptime = SystemBridge.getUptime()
    @State private var diskFree = SystemBridge.getDiskFree()

    // Volume via CoreAudio is instant (<1ms), Spotify needs AppleScript cache
    @State private var volume = SystemBridge.getVolume()
    @State private var spotify = SystemBridge.getCachedSpotify()

    // Slow data loaded from cache synchronously (instant if cached, empty if not)
    private static let serverNames = ["raven", "harbor"]
    @State private var weather = AsyncData.getCachedWeather()
    @State private var exchange = AsyncData.getCachedExchange()
    @State private var servers = AsyncData.getCachedServers(serverNames)
    @State private var agenda = AsyncData.getCachedCalendar()

    private let serverScript = "days=$(( $(cut -d. -f1 /proc/uptime) / 86400 )); load=$(cut -d\\\" \\\" -f1 /proc/loadavg); eval $(awk \\'/MemTotal/{printf \\\"total=%d \\\", $2/1048576} /MemAvailable/{printf \\\"avail=%d\\\", $2/1048576}\\' /proc/meminfo); used=$((total-avail)); ct=$(docker ps -q 2>/dev/null | wc -l | tr -d \\\" \\\"); echo \"${days}d  load $load  ${used}/${total}G  containers $ct\""

    // Tracks whether initial render is done (suppresses entry animations)
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 0) {
                clockSection
                gaugesSection
                    .padding(.top, 28)
                systemInfoRow
                    .padding(.top, 16)
                mediaSection
                    .frame(height: 20)
                    .clipped()
                    .opacity(spotify.state != "off" ? 1 : 0)
                    .padding(.top, 20)
                if battery != nil && !(battery!.acPower && battery!.percent >= 99) {
                    batterySection
                        .padding(.top, 16)
                }
                if !agenda.isEmpty {
                    agendaSection
                        .padding(.top, 24)
                }
                if !servers.isEmpty {
                    serversSection
                        .padding(.top, 24)
                }
                if !exchange.isEmpty {
                    exchangeSection
                        .padding(.top, 24)
                }
                if weather != nil {
                    weatherSection
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
                volume = SystemBridge.getVolume()
                privacyMode = SystemBridge.isPrivacyMode()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: "fast") {
            volume = SystemBridge.getVolume()
            spotify = SystemBridge.getSpotify()
            appeared = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                refreshFast()
            }
        }
        .task(id: "slow") {
            async let w = AsyncData.getWeather()
            async let e = AsyncData.getExchange()
            async let s = AsyncData.getServers(Self.serverNames, healthScript: serverScript)
            async let c = AsyncData.getTodayEvents()
            let newWeather = await w
            let newExchange = await e
            let newServers = await s
            let newAgenda = await c
            if let nw = newWeather { weather = nw }
            if !newExchange.isEmpty { exchange = newExchange }
            if !newServers.isEmpty { servers = newServers }
            if !newAgenda.isEmpty { agenda = newAgenda }
        }
    }

    private func formatBatteryTime(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m remaining" }
        if h > 0 { return "\(h)h remaining" }
        return "\(m)m remaining"
    }

    private func refreshFast() {
        cpu = SystemBridge.getCPU()
        ram = SystemBridge.getRAM()
        temp = SystemBridge.getTemp()
        battery = SystemBridge.getBattery()
        volume = SystemBridge.getVolume()
        spotify = SystemBridge.getSpotify()
        uptime = SystemBridge.getUptime()
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

    private var worldClockRow: some View {
        let local = TimeZone.current.identifier
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let clocks = Self.worldClocks.filter { $0.tz != local }.compactMap { city -> (String, String)? in
            guard let tz = TimeZone(identifier: city.tz) else { return nil }
            fmt.timeZone = tz
            return (city.label, fmt.string(from: time))
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

    private var gaugesSection: some View {
        HStack(spacing: 36) {
            CircularGauge(value: cpu, label: "CPU", color: .gaugeCyan, suffix: "%", animate: appeared)
            CircularGauge(value: ram, label: "RAM", color: .gaugePurple, suffix: "%", animate: appeared)
            CircularGauge(value: temp, label: "TEMP", color: .gaugeTeal, suffix: "°C", animate: appeared)
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
        if b.charging { return "battery.100percent.bolt" }
        if b.percent > 75 { return "battery.100percent" }
        if b.percent > 50 { return "battery.75percent" }
        if b.percent > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private var batterySection: some View {
        HStack(spacing: 8) {
            Image(systemName: batteryIcon)
                .font(.system(size: 13))
                .foregroundStyle(battery!.charging ? Color.yellow : batteryColor)
            Text("\(battery!.percent)%")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
            if battery!.charging {
                Text("charging")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.subtle)
            } else if let mins = battery?.timeRemaining {
                Text(formatBatteryTime(mins))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.subtle)
            }
            Spacer()
        }
    }

    private var batteryColor: Color {
        guard let b = battery else { return .white }
        if b.percent > 50 { return .green }
        if b.percent > 20 { return .yellow }
        return .red
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Today")
            ForEach(Array(agenda.enumerated()), id: \.element.id) { index, event in
                HStack(spacing: 10) {
                    Text(event.time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.subtle)
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    if index == 0 {
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

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Servers")
            ForEach(servers) { server in
                HStack(spacing: 10) {
                    Circle()
                        .fill(server.ok ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 60, alignment: .leading)
                    Text(server.info)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.subtle)
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

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Weather")
            HStack(spacing: 12) {
                Text(weather!.location.capitalized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text(weather!.condition)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.subtle)
                Text(weather!.temp)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
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

struct CircularGauge: View {
    let value: Int
    let label: String
    let color: Color
    var suffix: String = ""
    var animate: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animate ? .easeInOut(duration: 0.4) : nil, value: value)
            VStack(spacing: 2) {
                Text("\(value)\(suffix)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
            }
        }
        .frame(width: 80, height: 80)
    }
}
