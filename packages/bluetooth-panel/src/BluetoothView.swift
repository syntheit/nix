import SwiftUI

struct BluetoothView: View {
    @ObservedObject var manager: BluetoothManager
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Accent.blue)

                Text("Bluetooth")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { manager.togglePower() }) {
                    Text(manager.isPowered ? "ON" : "OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(manager.isPowered ? Accent.green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(manager.isPowered ? Accent.green.opacity(0.15) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if manager.isPowered {
                if manager.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bluetooth")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No paired devices")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    deviceList
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 28))
                        .foregroundColor(Accent.subtext)
                    Text("Bluetooth is off")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }

            Spacer(minLength: 8)
        }
        .padding(.bottom, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .onAppear { manager.refresh() }
    }

    private var deviceList: some View {
        VStack(spacing: 2) {
            ForEach(Array(manager.devices.enumerated()), id: \.element.id) { index, device in
                deviceRow(device, isSelected: index == selectedIndex)
                    .onTapGesture {
                        selectedIndex = index
                        toggleConnection(device)
                    }
            }
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(manager.devices.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < manager.devices.count {
                toggleConnection(manager.devices[selectedIndex])
            }
            return .handled
        }
    }

    private func deviceRow(_ device: BluetoothManager.Device, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.icon)
                .font(.system(size: 16))
                .foregroundColor(device.isConnected ? Accent.blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(device.isConnected ? "Connected" : "Not Connected")
                    .font(.system(size: 11))
                    .foregroundColor(device.isConnected ? Accent.green : .secondary)
            }

            Spacer()

            if let battery = device.batteryLevel {
                HStack(spacing: 3) {
                    Image(systemName: batteryIcon(battery))
                        .font(.system(size: 12))
                        .foregroundColor(batteryColor(battery))
                    Text("\(battery)%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: device.isConnected ? "xmark.circle" : "link.circle")
                    .font(.system(size: 16))
                    .foregroundColor(device.isConnected ? Accent.red.opacity(0.7) : Accent.blue.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
        )
        .padding(.horizontal, 4)
    }

    private func toggleConnection(_ device: BluetoothManager.Device) {
        if device.isConnected {
            manager.disconnect(device)
        } else {
            manager.connect(device)
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        if level > 75 { return "battery.100percent" }
        if level > 50 { return "battery.75percent" }
        if level > 25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private func batteryColor(_ level: Int) -> Color {
        if level > 50 { return Accent.green }
        if level > 20 { return Accent.yellow }
        return Accent.red
    }
}
