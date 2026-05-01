import SwiftUI

struct SystemDetailView: View {
    let detail: AsyncData.ServerDetail?
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(host)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                if let d = detail, !d.ok {
                    Text("offline")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red)
                }
                Spacer()
                Text("esc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.dimmed)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let d = detail {
                if d.ok {
                    cpuRamSection(d)
                    if let gpu = d.gpu { gpuSection(gpu) }
                    if !d.pools.isEmpty {
                        poolsSection(d.pools)
                    } else if !d.mounts.isEmpty {
                        mountsSection(d.mounts)
                    }
                    networkSection(d)
                    if let docker = d.dockerRunning, docker > 0 {
                        labeledRow(label: "docker", value: "\(docker) running")
                    }
                    if d.jellyfinStreams != nil || d.minecraft != nil {
                        servicesSection(d)
                    }
                } else {
                    Text("Unable to reach \(host).")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.subtle)
                }
            } else {
                Text("loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.subtle)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.black)
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThickMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    // MARK: - Sections

    private func cpuRamSection(_ d: AsyncData.ServerDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(label: "CPU",
                      value: d.cpuPercent, color: .gaugeCyan,
                      trailing: d.cpuTemp.map { "\($0)°" })
            metricRow(label: "RAM",
                      value: d.ramPercent, color: .gaugePurple,
                      overlay: d.memCompressed,
                      trailing: d.uptimeSecs.map { "up \(Format.uptime($0))" })
        }
    }

    private func gpuSection(_ g: AsyncData.GPUDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(label: "GPU",
                      value: g.utilPercent, color: .gaugeTeal,
                      trailing: "\(g.temp)° · \(Int(g.powerWatts))W")
            HStack {
                Text(g.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dimmed)
                Spacer()
                Text("\(Format.megabytes(g.memUsedMB)) / \(Format.megabytes(g.memTotalMB))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.subtle)
            }
            .padding(.leading, 94)
        }
    }

    private func poolsSection(_ pools: [AsyncData.PoolDetail]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pools) { pool in
                HStack(spacing: 6) {
                    metricRow(
                        label: pool.name,
                        value: pool.usagePercent,
                        color: .gaugeCyan,
                        trailing: "\(Format.bytes(pool.usedBytes)) / \(Format.bytes(pool.totalBytes))"
                    )
                    if pool.health != "ONLINE" {
                        Text(pool.health)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.yellow)
                    }
                }
            }
        }
    }

    private func mountsSection(_ mounts: [AsyncData.MountDetail]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(mounts) { m in
                metricRow(
                    label: m.mountpoint,
                    value: m.usagePercent,
                    color: .gaugeCyan,
                    trailing: "\(Format.bytes(m.usedBytes)) / \(Format.bytes(m.totalBytes))"
                )
            }
        }
    }

    private func networkSection(_ d: AsyncData.ServerDetail) -> some View {
        HStack(spacing: 12) {
            Text("net")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.dimmed)
                .frame(width: 84, alignment: .leading)
            Image(systemName: "arrow.down")
                .font(.system(size: 9))
                .foregroundStyle(Color.dimmed)
            Text(Format.rate(d.rxBytesPerSec))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.subtle)
            Image(systemName: "arrow.up")
                .font(.system(size: 9))
                .foregroundStyle(Color.dimmed)
            Text(Format.rate(d.txBytesPerSec))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.subtle)
            Spacer()
        }
    }

    @ViewBuilder
    private func servicesSection(_ d: AsyncData.ServerDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let streams = d.jellyfinStreams {
                labeledRow(
                    label: "jellyfin",
                    value: streams == 0 ? "idle" : "\(streams) streaming"
                )
            }
            if let mc = d.minecraft {
                labeledRow(
                    label: "minecraft",
                    value: mc.online
                        ? "\(mc.players)/\(mc.maxPlayers) players"
                        : "offline"
                )
            }
        }
    }

    private func labeledRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.dimmed)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.subtle)
            Spacer()
        }
    }

    private func metricRow(
        label: String,
        value: Int,
        color: Color,
        overlay: Int? = nil,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.dimmed)
                .frame(width: 84, alignment: .leading)
            ProgressBar(value: value, overlay: overlay ?? 0, color: color)
                .frame(height: 6)
            Text("\(value)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.subtle)
                .frame(width: 38, alignment: .trailing)
            if let t = trailing {
                Text(t)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.dimmed)
            }
        }
    }
}

// Internal flat progress bar — distinct from MiniBar in DashboardView, which
// is sized for the inline systems row. This one fills the available width.
private struct ProgressBar: View {
    let value: Int
    let overlay: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                if overlay > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.4))
                        .frame(width: geo.size.width * CGFloat(min(100, overlay)) / 100)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(100, value)) / 100)
            }
        }
    }
}

