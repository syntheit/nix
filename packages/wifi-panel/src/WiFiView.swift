import SwiftUI

struct WiFiView: View {
    @ObservedObject var manager: NetworkManager
    let speedtestPath: String
    @State private var selectedNetwork: String?
    @State private var passwordInput = ""
    @State private var showQR = false
    @State private var copiedIP = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().padding(.vertical, 8)

            if let net = manager.currentNetwork {
                connectionInfo(net)
                Divider().padding(.vertical, 8)
                quickActions
                Divider().padding(.vertical, 8)
            }

            networksSection

            Spacer(minLength: 8)
        }
        .padding(.bottom, 8)
        .frame(width: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            manager.refreshCurrent()
            manager.scan()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "wifi")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Accent.blue)

            Text("Wi-Fi")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if let net = manager.currentNetwork {
                Text(net.ssid)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Connection Info

    private func connectionInfo(_ net: NetworkManager.NetworkInfo) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                signalIcon(net.signalStrength)
                    .font(.system(size: 16))
                    .foregroundColor(Accent.green)

                Text(net.ssid)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                Text(net.security)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)))

                Spacer()

                Text("Ch \(net.channel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            if let info = manager.ipInfo {
                HStack(spacing: 0) {
                    infoChip(info.localIP)
                    Text("  \u{00B7}  ").foregroundColor(Accent.subtext).font(.system(size: 11))
                    infoChip("GW " + info.gateway)
                    if let pub = info.publicIP {
                        Text("  \u{00B7}  ").foregroundColor(Accent.subtext).font(.system(size: 11))
                        infoChip(pub)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                if !info.dns.isEmpty {
                    HStack(spacing: 0) {
                        Text("DNS ")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(info.dns.prefix(2).joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Speed test result
            if let speed = manager.speedResult {
                HStack(spacing: 12) {
                    speedChip(icon: "arrow.down.circle", label: speed.download)
                    speedChip(icon: "arrow.up.circle", label: speed.upload)
                    speedChip(icon: "network", label: speed.ping)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            // Revealed password
            if let pw = manager.revealedPassword {
                HStack {
                    Text(pw)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pw, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            // QR Code
            if showQR, let qr = manager.qrImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 8) {
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
            actionButton(icon: "qrcode", label: showQR ? "Hide QR" : "QR") {
                if showQR {
                    showQR = false
                } else {
                    manager.generateQR()
                    showQR = true
                }
            }
            if manager.isTestingSpeed {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Testing...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                actionButton(icon: "bolt", label: "Speed") {
                    manager.runSpeedTest(speedtestPath: speedtestPath)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Networks

    private var networksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Saved Networks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button(action: {
                    // Open WiFi settings for new network connections
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open WiFi Settings")

                if manager.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: { manager.scan() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(manager.availableNetworks.filter { !$0.isCurrentNetwork }) { network in
                        networkRow(network)
                    }
                }
            }
            .frame(maxHeight: 200)
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
                HStack(spacing: 10) {
                    if network.isSecure {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 14)
                    } else {
                        Color.clear.frame(width: 14)
                    }

                    Text(network.ssid)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    signalBars(network.signalBars)

                    Text("\(network.signalStrength)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Accent.subtext)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selectedNetwork == network.ssid {
                HStack(spacing: 8) {
                    if network.isSecure {
                        SecureField("Password", text: $passwordInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Accent.blue))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedNetwork == network.ssid ? Color.white.opacity(0.06) : Color.clear)
        )
        .padding(.horizontal, 4)
    }

    // MARK: - Components

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
    }

    private func speedChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Accent.blue)
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Accent.blue)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func signalIcon(_ rssi: Int) -> Image {
        if rssi > -80 { return Image(systemName: "wifi") }
        return Image(systemName: "wifi.exclamationmark")
    }

    private func signalBars(_ bars: Int) -> some View {
        HStack(spacing: 1.5) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Accent.blue : Color.white.opacity(0.15))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }
}
