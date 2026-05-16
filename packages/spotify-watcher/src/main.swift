import Foundation
import AppKit

let sketchybarBin = ProcessInfo.processInfo.environment["SKETCHYBAR_BIN"]
    ?? "/run/current-system/sw/bin/sketchybar"

func trigger(state: String, title: String = "", artist: String = "") {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: sketchybarBin)
    task.arguments = [
        "--trigger", "spotify_change",
        "STATE=\(state.lowercased())",
        "TITLE=\(title)",
        "ARTIST=\(artist)",
    ]
    do {
        try task.run()
    } catch {
        FileHandle.standardError.write(
            Data("spotify-watcher: trigger failed: \(error)\n".utf8))
    }
}

let dnc = DistributedNotificationCenter.default()
dnc.addObserver(
    forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
    object: nil,
    queue: .main
) { notif in
    let info = notif.userInfo ?? [:]
    trigger(
        state: info["Player State"] as? String ?? "",
        title: info["Name"] as? String ?? "",
        artist: info["Artist"] as? String ?? ""
    )
}

let wnc = NSWorkspace.shared.notificationCenter
wnc.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification,
    object: nil,
    queue: .main
) { notif in
    guard
        let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.bundleIdentifier == "com.spotify.client"
    else { return }
    trigger(state: "stopped")
}

RunLoop.main.run()
