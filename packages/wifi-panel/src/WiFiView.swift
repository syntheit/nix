import SwiftUI

struct WiFiView: View {
    @ObservedObject var manager: NetworkManager
    let speedtestPath: String
    @State private var selectedNetwork: String?
    @State private var passwordInput = ""
    @State private var showQR = false
    @State private var copiedIP = false
    @State private var showNetworks = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: wifi icon + SSID
            if let net = manager.currentNetwork {
                HStack(spacing: 10) {
                    signalIcon(net.signalStrength)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Accent.green)

                    Text(net.ssid)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(net.security)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))

                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)
            } else {
                HStack {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Not Connected")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }

            separator

            // Quick actions
            if manager.currentNetwork != nil {
                quickActions
                    .padding(.vertical, 10)
                separator
            }

            // Network Details
            if let net = manager.currentNetwork, let info = manager.ipInfo {
                detailsSection(net, info)
                    .padding(.vertical, 10)
                separator
            }

            // Speed test result
            if let speed = manager.speedResult {
                speedSection(speed)
                    .padding(.vertical, 10)
                separator
            }

            // Revealed password
            if let pw = manager.revealedPassword {
                passwordSection(pw)
                    .padding(.vertical, 10)
                separator
            }

            // QR Code
            if showQR, let qr = manager.qrImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .background(Color.white)
                    .cornerRadius(10)
                    .padding(.vertical, 10)
                separator
            }

            // Networks (collapsible)
            networksSection
                .padding(.top, 10)

            Spacer(minLength: 12)
        }
        .frame(width: 560)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            manager.refreshCurrent()
            manager.scan()
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            actionButton(icon: "doc.on.doc", label: copiedIP ? "Copied" : "Copy IP") {
                if let ip = manager.ipInfo?.localIP {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                    copiedIP = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedIP = false }
                }
            }
            actionButton(icon: "key", label: "Password") {
                manager.revealPassword()
            }
            actionButton(icon: "qrcode", label: showQR ? "Hide" : "QR Code") {
                if showQR { showQR = false } else { manager.generateQR(); showQR = true }
            }
            if manager.isTestingSpeed {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Testing...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            } else {
                actionButton(icon: "bolt", label: "Speed") {
                    manager.runSpeedTest(speedtestPath: speedtestPath)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Network Details

    private func detailsSection(_ net: NetworkManager.NetworkInfo, _ info: NetworkManager.IPInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 28)

            let rows: [(String, String)] = [
                ("IP Address", info.localIP),
                ("Gateway", info.gateway),
                ("Public IP", info.publicIP ?? "..."),
                ("DNS", info.dns.prefix(2).joined(separator: ", ")),
                ("Channel", "\(net.channel)"),
                ("Interface", info.interfaceName),
            ]

            ForEach(rows, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(value)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    // MARK: - Speed Result

    private func speedSection(_ speed: NetworkManager.SpeedResult) -> some View {
        HStack(spacing: 16) {
            speedChip(icon: "arrow.down.circle.fill", label: speed.download, color: Accent.green)
            speedChip(icon: "arrow.up.circle.fill", label: speed.upload, color: Accent.blue)
            speedChip(icon: "network", label: speed.ping, color: Accent.yellow)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Password

    private func passwordSection(_ pw: String) -> some View {
        HStack {
            Image(systemName: "key.fill")
                .font(.system(size: 12))
                .foregroundStyle(Accent.yellow)
            Text(pw)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pw, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Networks (collapsible)

    private var networksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showNetworks.toggle() } }) {
                HStack {
                    Text("Saved Networks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image(systemName: showNetworks ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if manager.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: { manager.scan() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showNetworks {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(manager.availableNetworks.filter { !$0.isCurrentNetwork }) { network in
                            networkRow(network)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 200)
                .transition(.opacity)
            }
        }
    }

    private func networkRow(_ network: NetworkManager.AvailableNetwork) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                if selectedNetwork == network.ssid {
                    selectedNetwork = nil
                } else {
                    selectedNetwork = network.ssid
                    passwordInput = ""
                }
            }) {
                HStack(spacing: 12) {
                    if network.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                    } else {
                        Color.clear.frame(width: 16)
                    }

                    Text(network.ssid)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if network.signalStrength != 0 {
                        signalBars(network.signalBars)
                        Text("\(network.signalStrength)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Accent.subtext)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selectedNetwork == network.ssid {
                HStack(spacing: 10) {
                    if network.isSecure {
                        SecureField("Password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onSubmit {
                                manager.connect(ssid: network.ssid, password: passwordInput)
                                selectedNetwork = nil
                            }
                    }
                    Button(action: {
                        manager.connect(ssid: network.ssid, password: passwordInput)
                        selectedNetwork = nil
                    }) {
                        Text("Connect")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Accent.blue))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedNetwork == network.ssid ? Color.white.opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Components

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func speedChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Accent.blue)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func signalIcon(_ rssi: Int) -> Image {
        if rssi > -80 { return Image(systemName: "wifi") }
        return Image(systemName: "wifi.exclamationmark")
    }

    private func signalBars(_ bars: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Accent.blue : Color.white.opacity(0.15))
                    .frame(width: 4, height: CGFloat(5 + i * 3))
            }
        }
    }
}
