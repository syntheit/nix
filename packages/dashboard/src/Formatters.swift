import Foundation

enum Format {
    static func rate(_ bytesPerSec: Int64) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", Double(bytesPerSec) / 1_048_576)
        }
        if bytesPerSec >= 1024 {
            return "\(bytesPerSec / 1024)K"
        }
        return "\(bytesPerSec)B"
    }

    static func uptime(_ secs: Int) -> String {
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        if d > 0 { return "\(d)d" }
        return "\(h)h"
    }

    static func bytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1024 { return String(format: "%.1fT", gb / 1024) }
        if gb >= 10 { return String(format: "%.0fG", gb) }
        return String(format: "%.1fG", gb)
    }

    static func megabytes(_ mb: Int) -> String {
        if mb >= 1024 { return String(format: "%.1fG", Double(mb) / 1024) }
        return "\(mb)M"
    }
}
