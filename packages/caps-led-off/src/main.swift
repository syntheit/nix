import Foundation
import AppKit
import IOKit
import IOKit.hidsystem

func clearCapsLock() {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
    guard service != 0 else { return }
    defer { IOObjectRelease(service) }

    var conn: io_connect_t = 0
    guard IOServiceOpen(
        service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS
    else { return }
    defer { IOServiceClose(conn) }

    _ = IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), false)
}

clearCapsLock()

let wnc = NSWorkspace.shared.notificationCenter
wnc.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil, queue: .main
) { _ in clearCapsLock() }

wnc.addObserver(
    forName: NSWorkspace.screensDidWakeNotification,
    object: nil, queue: .main
) { _ in clearCapsLock() }

RunLoop.main.run()
