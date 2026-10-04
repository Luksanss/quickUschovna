// Sends a command to a running Debug build of quickUschovna (`quickUschovna/App/DebugControl.swift`).
// Usage: xcrun swift scripts/debug-control.swift <command> [args…]
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("usage: debug-control.swift <command> [args…]")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.luksanss.quickUschovna.debug"), object: command,
    userInfo: ["args": Array(arguments.dropFirst())], deliverImmediately: true)
