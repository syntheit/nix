import AppKit

struct AppEntry: Identifiable {
    let id: String
    let name: String
    let path: String
    let icon: NSImage
}

class AppIndexer {
    private(set) var apps: [AppEntry] = []
    private var recents: [String: (timestamp: TimeInterval, count: Int)] = [:]
    private let recentsPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = "\(home)/.config/search-panel"
        recentsPath = "\(configDir)/recents.json"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        loadRecents()
        indexApps()
    }

    func indexApps() {
        var found: [AppEntry] = []
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]

        let ws = NSWorkspace.shared
        let fm = FileManager.default

        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                if item.hasPrefix(".") { continue }
                let path = "\(dir)/\(item)"
                if item.hasSuffix(".app") {
                    if isHiddenApp(at: path) { continue }
                    let name = (item as NSString).deletingPathExtension
                    let icon = ws.icon(forFile: path)
                    icon.size = NSSize(width: 32, height: 32)
                    found.append(AppEntry(id: path, name: name, path: path, icon: icon))
                } else if dir == "/Applications" {
                    // Check one level deep for app bundles in subfolders
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard let subItems = try? fm.contentsOfDirectory(atPath: path) else { continue }
                    for sub in subItems where sub.hasSuffix(".app") && !sub.hasPrefix(".") {
                        let subPath = "\(path)/\(sub)"
                        if isHiddenApp(at: subPath) { continue }
                        let name = (sub as NSString).deletingPathExtension
                        let icon = ws.icon(forFile: subPath)
                        icon.size = NSSize(width: 32, height: 32)
                        found.append(AppEntry(id: subPath, name: name, path: subPath, icon: icon))
                    }
                }
            }
        }

        // Deduplicate by name (prefer /Applications over /System/Applications)
        var seen = Set<String>()
        apps = found.filter { seen.insert($0.name.lowercased()).inserted }
    }

    /// Filter out background-only and agent apps (no dock icon, not user-facing)
    private func isHiddenApp(at path: String) -> Bool {
        guard let bundle = Bundle(path: path),
              let info = bundle.infoDictionary else { return false }

        for key in ["LSUIElement", "LSBackgroundOnly"] {
            if let val = info[key] {
                if let b = val as? Bool, b { return true }
                if let s = val as? String, s == "1" || s.lowercased() == "yes" || s.lowercased() == "true" { return true }
                if let n = val as? Int, n == 1 { return true }
            }
        }
        return false
    }

    private func runningAppPaths() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            return app.bundleURL?.path
        })
    }

    func search(_ query: String) -> [AppEntry] {
        if query.isEmpty {
            let running = runningAppPaths()
            return Array(apps.sorted { a, b in
                let aRunning = running.contains(a.path)
                let bRunning = running.contains(b.path)
                if aRunning != bRunning { return aRunning }
                let aR = recents[a.path]
                let bR = recents[b.path]
                if let aT = aR?.timestamp, let bT = bR?.timestamp {
                    if aT != bT { return aT > bT }
                } else if aR != nil {
                    return true
                } else if bR != nil {
                    return false
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }.prefix(8))
        }

        let q = query.lowercased()
        return Array(apps.filter { app in
            let name = app.name.lowercased()
            if name.contains(q) { return true }
            // Initials match (e.g., "ss" matches "System Settings")
            let initials = String(app.name.split(separator: " ").compactMap(\.first))
            return initials.lowercased().hasPrefix(q)
        }.sorted { a, b in
            let aName = a.name.lowercased()
            let bName = b.name.lowercased()
            // Exact match first (guard against both matching)
            if aName == q && bName != q { return true }
            if bName == q && aName != q { return false }
            // Prefix match
            let aPrefix = aName.hasPrefix(q)
            let bPrefix = bName.hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            // Word-start match
            let aWordStart = aName.split(separator: " ").contains { String($0).lowercased().hasPrefix(q) }
            let bWordStart = bName.split(separator: " ").contains { String($0).lowercased().hasPrefix(q) }
            if aWordStart != bWordStart { return aWordStart }
            // Recency
            let aT = recents[a.path]?.timestamp ?? 0
            let bT = recents[b.path]?.timestamp ?? 0
            if aT != bT { return aT > bT }
            return aName < bName
        }.prefix(8))
    }

    func recordLaunch(_ app: AppEntry) {
        let existing = recents[app.path]
        recents[app.path] = (Date().timeIntervalSince1970, (existing?.count ?? 0) + 1)
        saveRecents()
    }

    private func loadRecents() {
        guard let data = FileManager.default.contents(atPath: recentsPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return }
        for (path, info) in dict {
            if let t = info["t"] as? TimeInterval, let c = info["c"] as? Int {
                recents[path] = (t, c)
            }
        }
    }

    private func saveRecents() {
        var dict: [String: [String: Any]] = [:]
        for (path, info) in recents {
            dict[path] = ["t": info.timestamp, "c": info.count]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: URL(fileURLWithPath: recentsPath))
    }
}
