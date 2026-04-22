import SwiftUI

struct VolumeView: View {
    @ObservedObject var audio: AudioManager
    var onResize: (NSSize) -> Void
    var onDismissCancel: () -> Void
    var onDismissRestore: () -> Void

    @State private var isExpanded = false
    @State private var eqEnabled = false
    @State private var eqBass: Float = 0
    @State private var eqMid: Float = 0
    @State private var eqTreble: Float = 0
    @State private var eqAvailable = false

    private let compactSize = NSSize(width: 340, height: 96)
    private let expandedSize = NSSize(width: 340, height: 460)

    var body: some View {
        VStack(spacing: 0) {
            compactView
            if isExpanded {
                expandedView
                    .transition(.opacity)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .onHover { hovering in
            if hovering && !isExpanded {
                onDismissCancel()
                withAnimation(.easeOut(duration: 0.25)) { isExpanded = true }
                onResize(expandedSize)
                loadEQStatus()
            }
        }
    }

    // MARK: - Compact (matches native macOS HUD)

    private var compactView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Volume")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                        Capsule()
                            .fill(.white)
                            .frame(width: max(4, geo.size.width * CGFloat(audio.isMuted ? 0 : audio.volume)))
                    }
                }
                .frame(height: 6)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 340)
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Output devices
            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 20)

                ForEach(audio.devices) { device in
                    Button(action: { audio.setOutputDevice(device.id) }) {
                        HStack(spacing: 10) {
                            Image(systemName: device.isDefault ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(device.isDefault ? Accent.blue : .secondary)
                                .frame(width: 20)

                            Image(systemName: device.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .frame(width: 18)

                            Text(device.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if eqAvailable {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                eqSection
            }

            Spacer(minLength: 8)
        }
    }

    // MARK: - EQ

    private var eqSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Equalizer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button(action: {
                    audio.eqCommand(eqEnabled ? "off" : "on")
                    eqEnabled.toggle()
                }) {
                    Text(eqEnabled ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(eqEnabled ? Accent.green : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(eqEnabled ? Accent.green.opacity(0.15) : .white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            if eqEnabled {
                eqSlider(label: "Bass", value: $eqBass, command: "bass")
                eqSlider(label: "Mid", value: $eqMid, command: "mid")
                eqSlider(label: "Treble", value: $eqTreble, command: "treble")
            }
        }
    }

    private func eqSlider(label: String, value: Binding<Float>, command: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(width: 46, alignment: .leading)

            Slider(value: value, in: -24...24, step: 1) { editing in
                if !editing {
                    audio.eqCommand("\(command) \(value.wrappedValue)")
                }
            }
            .tint(Accent.blue)

            Text(String(format: "%+.0f", value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func loadEQStatus() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let status = audio.eqStatus() {
                DispatchQueue.main.async {
                    eqAvailable = true
                    eqEnabled = status.enabled
                    eqBass = status.bass
                    eqMid = status.mid
                    eqTreble = status.treble
                }
            }
        }
    }
}
