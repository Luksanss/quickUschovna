import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared with the extensions of `AppDelegate` that receive files from outside, like the Quick Action.
    let model = AppModel()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIconRenderer.image(for: model.iconState)
        statusItem = item
    }
}
