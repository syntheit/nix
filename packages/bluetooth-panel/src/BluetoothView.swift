import SwiftUI

struct BluetoothView: View {
    @ObservedObject var manager: BluetoothManager
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Accent.blue)

                Text("Bluetooth")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { manager.togglePower() }) {
                    Text(manager.isPowered ? "ON" : "OFF")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(manager.isPowered ? Accent.green : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(manager.isPowered ? Accent.green.opacity(0.15) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 20)

            if manager.isPowered {
                if manager.devices.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bluetooth")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No paired devices")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(manager.devices.enumerated()), id: \.element.id) { index, device in
                                deviceRow(device, isSelected: index == selectedIndex)
                                    .onTapGesture {
                                        selectedIndex = index
                                        toggleConnection(device)
                                    }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 8)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 36))
                        .foregroundStyle(Accent.subtext)
                    Text("Bluetooth is off")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .frame(width: 560, height: 440)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .onAppear { manager.refresh() }
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
        HStack(spacing: 16) {
            Image(systemName: device.icon)
                .font(.system(size: 22))
                .foregroundStyle(device.isConnected ? Accent.blue : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text(device.isConnected ? "Connected" : "Not Connected")
                    .font(.system(size: 12))
                    .foregroundStyle(device.isConnected ? Accent.green : .secondary)
            }

            Spacer()

            if let battery = device.batteryLevel {
                HStack(spacing: 5) {
                    Image(systemName: batteryIcon(battery))
                        .font(.system(size: 14))
                        .foregroundStyle(batteryColor(battery))
                    Text("\(battery)%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: { toggleConnection(device) }) {
                    Text(device.isConnected ? "Disconnect" : "Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(device.isConnected ? Accent.red : Accent.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(device.isConnected ? Accent.red.opacity(0.1) : Accent.blue.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
        )
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

// MARK: - Compact Dropdown View

struct BluetoothDropdownView: View {
    @ObservedObject var manager: BluetoothManager
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    private var connectedDevices: [BluetoothManager.Device] {
        manager.devices.filter { $0.isConnected }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bluetooth")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                ToggleSwitch(isOn: manager.isPowered) {
                    manager.togglePower()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            dropdownSeparator

            if manager.isPowered && !connectedDevices.isEmpty {
                VStack(spacing: 2) {
                    ForEach(connectedDevices) { device in
                        dropdownDeviceRow(device)
                    }
                }
                .padding(.vertical, 6)

                dropdownSeparator
            }

            Button(action: {
                onDismiss()
                onOpenSettings()
            }) {
                HStack {
                    Text("Bluetooth Settings...")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 252)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private func dropdownDeviceRow(_ device: BluetoothManager.Device) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: device.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                )

            Text(device.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            if let battery = device.batteryLevel {
                Text("\(battery)%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var dropdownSeparator: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }
}
