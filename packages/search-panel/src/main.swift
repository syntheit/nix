import AppKit
import SwiftUI

// MARK: - Unified Search Result

struct SearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let iconType: IconType
    let isCopyAction: Bool
    let action: () -> Void

    enum IconType {
        case app(NSImage)
        case symbol(String, Color)
        case emoji(String)
    }
}

// MARK: - System Commands

private let systemCommands: [(name: String, icon: String, color: Color, execute: () -> Void)] = [
    ("Lock Screen", "lock.fill", Accent.blue, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]; try? p.run()
    }),
    ("Sleep", "moon.fill", Accent.blue, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]; try? p.run()
    }),
    ("Restart", "arrow.clockwise", Accent.yellow, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to restart"]; try? p.run()
    }),
    ("Shut Down", "power", Accent.red, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to shut down"]; try? p.run()
    }),
    ("Log Out", "rectangle.portrait.and.arrow.right", Accent.subtext, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to log out"]; try? p.run()
    }),
    ("Empty Trash", "trash.fill", Accent.red, {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"Finder\" to empty the trash"]; try? p.run()
    }),
]

// MARK: - Search Model

class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0
    @Published var items: [SearchItem] = []
    @Published var copiedFlash = false

    var onResize: ((CGFloat) -> Void)?
    var onDismiss: (() -> Void)?
    let indexer = AppIndexer()
    let currency = CurrencyRates()

    var totalItems: Int { items.count }
    var hasResults: Bool { !items.isEmpty }

    func updateResults() {
        var newItems: [SearchItem] = []

        // Emoji mode (: prefix)
        if query.hasPrefix(":") && query.count > 1 {
            let emojiQuery = String(query.dropFirst())
            for emoji in EmojiStore.search(emojiQuery).prefix(8) {
                newItems.append(SearchItem(
                    id: "emoji-\(emoji.character)-\(emoji.name)",
                    title: emoji.name,
                    subtitle: nil,
                    iconType: .emoji(emoji.character),
                    isCopyAction: true,
                    action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(emoji.character, forType: .string)
                    }
                ))
            }
            items = newItems
            selectedIndex = 0
            onResize?(calculateHeight())
            return
        }

        // Math
        if let result = evaluateMath(query) {
            newItems.append(SearchItem(
                id: "math",
                title: "= \(result)",
                subtitle: query,
                iconType: .symbol("equal.circle.fill", Accent.blue),
                isCopyAction: true,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
            ))
        }

        // Currency
        for cr in currency.search(query) {
            newItems.append(SearchItem(
                id: cr.id,
                title: cr.title,
                subtitle: cr.subtitle,
                iconType: .symbol(cr.icon, cr.color),
                isCopyAction: true,
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cr.copyValue, forType: .string)
                }
            ))
        }

        // System commands
        if !query.isEmpty {
            let q = query.lowercased()
            for cmd in systemCommands where cmd.name.lowercased().contains(q) {
                let execute = cmd.execute
                newItems.append(SearchItem(
                    id: "sys-\(cmd.name)",
                    title: cmd.name,
                    subtitle: "System",
                    iconType: .symbol(cmd.icon, cmd.color),
                    isCopyAction: false,
                    action: execute
                ))
            }
        }

        // Apps
        newItems.append(contentsOf: appItems(from: indexer.search(query)))

        items = Array(newItems.prefix(8))
        selectedIndex = 0
        onResize?(calculateHeight())
    }

    func reset() {
        query = ""
        copiedFlash = false
        items = appItems(from: indexer.search(""))
        selectedIndex = 0
    }

    private func appItems(from apps: [AppEntry]) -> [SearchItem] {
        apps.map { app in
            SearchItem(
                id: app.id,
                title: app.name,
                subtitle: nil,
                iconType: .app(app.icon),
                isCopyAction: false,
                action: { [weak self] in
                    self?.indexer.recordLaunch(app)
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                }
            )
        }
    }

    func moveUp() {
        if selectedIndex > 0 { selectedIndex -= 1 }
    }

    func moveDown() {
        if selectedIndex < totalItems - 1 { selectedIndex += 1 }
    }

    @discardableResult
    func launchSelected() -> Bool {
        guard selectedIndex >= 0, selectedIndex < items.count else { return false }
        let item = items[selectedIndex]
        item.action()

        if item.isCopyAction {
            copiedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.copiedFlash = false
                self?.onDismiss?()
            }
        } else {
            onDismiss?()
        }
        return true
    }

    // MARK: - Height Calculation

    private let searchBarHeight: CGFloat = 62
    private let resultRowHeight: CGFloat = 46
    private let dividerSection: CGFloat = 7
    private let bottomPadding: CGFloat = 8

    func calculateHeight() -> CGFloat {
        var h = searchBarHeight
        if !items.isEmpty {
            h += dividerSection + CGFloat(items.count) * resultRowHeight + bottomPadding
        }
        return h
    }

    // MARK: - Math Evaluation (safe recursive descent parser)

    private func evaluateMath(_ input: String) -> String? {
        var trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("=") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !trimmed.isEmpty else { return nil }

        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard trimmed.contains(where: { $0.isNumber }) else { return nil }

        let afterFirst = trimmed.dropFirst()
        guard afterFirst.contains(where: { "+-*/".contains($0) }) else { return nil }

        var pos = trimmed.startIndex

        func skipSpaces() {
            while pos < trimmed.endIndex && trimmed[pos] == " " {
                pos = trimmed.index(after: pos)
            }
        }

        func peek() -> Character? {
            skipSpaces()
            return pos < trimmed.endIndex ? trimmed[pos] : nil
        }

        func parseNumber() -> Double? {
            skipSpaces()
            guard pos < trimmed.endIndex else { return nil }
            var numStr = ""
            while pos < trimmed.endIndex && (trimmed[pos].isNumber || trimmed[pos] == ".") {
                numStr.append(trimmed[pos])
                pos = trimmed.index(after: pos)
            }
            guard !numStr.isEmpty else { return nil }
            return Double(numStr)
        }

        func parseFactor() -> Double? {
            skipSpaces()
            guard pos < trimmed.endIndex else { return nil }
            if trimmed[pos] == "-" {
                pos = trimmed.index(after: pos)
                guard let val = parseFactor() else { return nil }
                return -val
            }
            if trimmed[pos] == "+" {
                pos = trimmed.index(after: pos)
                return parseFactor()
            }
            if trimmed[pos] == "(" {
                pos = trimmed.index(after: pos)
                guard let result = parseExpr() else { return nil }
                skipSpaces()
                guard pos < trimmed.endIndex && trimmed[pos] == ")" else { return nil }
                pos = trimmed.index(after: pos)
                return result
            }
            return parseNumber()
        }

        func parseTerm() -> Double? {
            guard var left = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                pos = trimmed.index(after: pos)
                guard let right = parseFactor() else { return nil }
                if op == "*" { left *= right }
                else {
                    if right == 0 { return nil }
                    left /= right
                }
            }
            return left
        }

        func parseExpr() -> Double? {
            guard var left = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                pos = trimmed.index(after: pos)
                guard let right = parseTerm() else { return nil }
                if op == "+" { left += right }
                else { left -= right }
            }
            return left
        }

        guard let result = parseExpr() else { return nil }
        skipSpaces()
        guard pos == trimmed.endIndex else { return nil }
        guard !result.isNaN, !result.isInfinite else { return nil }

        if result == floor(result) && abs(result) < 1e15 {
            return String(format: "%.0f", result)
        }
        return String(format: "%.10g", result)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: SystemPanel!
    var model: SearchModel!
    var keyMonitor: Any?
    var ipcServer: IPCServer!
    let panelWidth: CGFloat = 680

    static let socketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/search-panel/search.sock"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model = SearchModel()
        model.onResize = { [weak self] height in
            self?.updatePanelFrame(height: height)
        }
        model.onDismiss = { [weak self] in
            self?.dismissPanel()
        }

        panel = SystemPanel(size: NSSize(width: panelWidth, height: 62))

        ipcServer = IPCServer(path: Self.socketPath)
        ipcServer.handler = { [weak self] cmd in
            self?.handleCommand(cmd) ?? "ok"
        }
        ipcServer.start()

        installSignalHandlers()
    }

    func handleCommand(_ cmd: String) -> String {
        switch cmd {
        case "toggle":
            if panel.isVisible { dismissPanel() }
            else { showPanel() }
        case "show":
            if !panel.isVisible { showPanel() }
        case "hide":
            dismissPanel()
        default: break
        }
        return "ok"
    }

    func showPanel() {
        removeKeyMonitor()
        model.reset()

        let height = model.calculateHeight()
        panel.setFrame(NSRect(origin: .zero, size: NSSize(width: panelWidth, height: height)), display: false)
        panel.setContent(SearchView(model: model))
        panel.showAt(position: .center)

        repositionPanel(height: height)

        installKeyMonitor()
    }

    func dismissPanel() {
        panel.dismiss()
        removeKeyMonitor()
    }

    func repositionPanel(height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let topY = sf.maxY - sf.height * 0.28
        let origin = NSPoint(x: sf.midX - panelWidth / 2, y: topY - height)
        panel.setFrameOrigin(origin)
    }

    func updatePanelFrame(height: CGFloat) {
        guard panel.isVisible, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let topY = sf.maxY - sf.height * 0.28
        let origin = NSPoint(x: sf.midX - panelWidth / 2, y: topY - height)
        let frame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: height))

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(frame, display: true)
        }
    }

    func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel.isVisible else { return event }

            switch event.keyCode {
            case 125: // Down arrow
                self.model.moveDown()
                return nil
            case 126: // Up arrow
                self.model.moveUp()
                return nil
            case 36: // Return
                if self.model.totalItems > 0 {
                    self.model.launchSelected()
                }
                return nil
            case 48: // Tab
                if event.modifierFlags.contains(.shift) {
                    self.model.moveUp()
                } else {
                    self.model.moveDown()
                }
                return nil
            default:
                return event
            }
        }
    }

    func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    func installSignalHandlers() {
        signal(SIGTERM) { _ in
            unlink(AppDelegate.socketPath)
            exit(0)
        }
        signal(SIGINT) { _ in
            unlink(AppDelegate.socketPath)
            exit(0)
        }
        signal(SIGUSR1) { _ in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.model.indexer.indexApps()
            }
        }
    }
}

// MARK: - Entry Point

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty {
    fputs("usage: search-panel daemon|toggle|show|hide\n", stderr)
    exit(1)
}

if args[0] == "daemon" {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    if let response = sendIPC(args[0], socketPath: AppDelegate.socketPath) {
        print(response)
    } else {
        fputs("search-panel: daemon not running\n", stderr)
        exit(1)
    }
}
