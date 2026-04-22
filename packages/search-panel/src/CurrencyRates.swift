import AppKit
import SwiftUI

struct CurrencyResult {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    let copyValue: String
}

class CurrencyRates {
    private var rates: [String: Double] = [:]
    private var cryptoRates: [String: Double] = [:]
    private let cachePath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        cachePath = "\(home)/.config/search-panel/rates-cache.json"
        loadCache()
        fetch()
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func fetch() {
        guard let url = URL(string: "https://raw.githubusercontent.com/syntheit/exchange-rates/refs/heads/main/rates.json") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = json["rates"] as? [String: Double],
                  let cr = json["cryptoRates"] as? [String: Double]
            else { return }

            DispatchQueue.main.async {
                self?.rates = r
                self?.cryptoRates = cr
                self?.saveCache(data)
            }
        }.resume()
    }

    func search(_ query: String) -> [CurrencyResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.split(separator: " ")

        // "100 BRL" → convert amount
        if parts.count == 2, let amount = Double(parts[0]) {
            let code = String(parts[1])
            return convertFromCurrency(code: code, amount: amount)
        }

        // Single code: "BRL", "ARS", "BTC"
        if parts.count == 1, parts[0].count >= 3, parts[0].count <= 5,
           parts[0].allSatisfy({ $0.isLetter }) {
            let code = String(parts[0])

            // Crypto
            if let rate = cryptoRates[code] {
                return [makeCryptoItem(code: code, rate: rate)]
            }

            // Exact rate
            if let rate = rates[code] {
                return [makeRateItem(code: code, rate: rate, label: nil)]
            }

            // Split currencies (ARS_BLUE, ARS_OFFICIAL, BOB_BLUE, etc.)
            let matching = rates.filter { $0.key.hasPrefix(code + "_") }
                .sorted { $0.key < $1.key }
            if !matching.isEmpty {
                return matching.map { key, rate in
                    let label = String(key.dropFirst(code.count + 1))
                        .replacingOccurrences(of: "_", with: " ").capitalized
                    return makeRateItem(code: code, rate: rate, label: label)
                }
            }
        }

        return []
    }

    private func makeRateItem(code: String, rate: Double, label: String?) -> CurrencyResult {
        let formatted = formatRate(rate)
        return CurrencyResult(
            id: "fx-\(code)-\(label ?? "base")",
            title: "1 USD = \(formatted) \(code)",
            subtitle: label,
            icon: "dollarsign.circle.fill",
            color: Accent.green,
            copyValue: formatted
        )
    }

    private func makeCryptoItem(code: String, rate: Double) -> CurrencyResult {
        let formatted = formatRate(rate)
        return CurrencyResult(
            id: "crypto-\(code)",
            title: "1 \(code) = \(formatted) USD",
            subtitle: nil,
            icon: "bitcoinsign.circle.fill",
            color: Accent.yellow,
            copyValue: formatted
        )
    }

    private func convertFromCurrency(code: String, amount: Double) -> [CurrencyResult] {
        // Crypto
        if let rate = cryptoRates[code] {
            let usd = amount * rate
            return [CurrencyResult(
                id: "convert-\(code)",
                title: "\(formatRate(amount)) \(code) = \(formatRate(usd)) USD",
                subtitle: nil,
                icon: "arrow.left.arrow.right.circle.fill",
                color: Accent.blue,
                copyValue: formatRate(usd)
            )]
        }

        // Direct rate
        if let rate = rates[code] {
            let usd = amount / rate
            return [CurrencyResult(
                id: "convert-\(code)",
                title: "\(formatRate(amount)) \(code) = \(formatRate(usd)) USD",
                subtitle: nil,
                icon: "arrow.left.arrow.right.circle.fill",
                color: Accent.blue,
                copyValue: formatRate(usd)
            )]
        }

        // Split currencies — show all conversions
        let matching = rates.filter { $0.key.hasPrefix(code + "_") }.sorted { $0.key < $1.key }
        return matching.map { key, rate in
            let usd = amount / rate
            let label = String(key.dropFirst(code.count + 1))
                .replacingOccurrences(of: "_", with: " ").capitalized
            return CurrencyResult(
                id: "convert-\(key)",
                title: "\(formatRate(amount)) \(code) = \(formatRate(usd)) USD",
                subtitle: label,
                icon: "arrow.left.arrow.right.circle.fill",
                color: Accent.blue,
                copyValue: formatRate(usd)
            )
        }
    }

    private func formatRate(_ value: Double) -> String {
        if value >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 2
            return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else if value >= 0.01 {
            return String(format: "%.4f", value)
        } else {
            return String(format: "%.6f", value)
        }
    }

    private func loadCache() {
        guard let data = FileManager.default.contents(atPath: cachePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = json["rates"] as? [String: Double],
              let cr = json["cryptoRates"] as? [String: Double]
        else { return }
        rates = r
        cryptoRates = cr
    }

    private func saveCache(_ data: Data) {
        try? data.write(to: URL(fileURLWithPath: cachePath))
    }
}
