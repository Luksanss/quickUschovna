import AppKit

/// The menu-bar item: its icon follows `AppModel.iconState`, a click opens or closes the panel, and
/// files dropped on it are sent.
final class StatusItemController {
    private let model: AppModel
    /// A fixed width, the prototype's 32 pt item, so the icon's wider drag-over image (its accent
    /// highlight) doesn't push the items beside it around.
    private let item = NSStatusBar.system.statusItem(withLength: 32)
    private let drop = FileDrop()

    init(model: AppModel) {
        self.model = model
        guard let button = item.button else { return }
        button.setAccessibilityLabel("quickUschovna")
        button.target = self
        button.action = #selector(clicked)
        if let window = button.window {
            drop.onHover = { [weak model] over in model?.isDragOverIcon = over }
            drop.onDrop = { [weak model] urls in model?.send(urls) }
            drop.attach(to: window)
        }
        observe { [weak self] in self?.update() }
    }

    /// The item's frame on screen, which the surfaces hang from.
    var frameOnScreen: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// The bottom of the menu bar the item is in, and that bar's screen.
    var menuBarBottom: (y: CGFloat, screen: NSScreen)? {
        guard let window = item.button?.window, let screen = window.screen else { return nil }
        return (window.frame.minY, screen)
    }

    private func update() {
        guard let button = item.button else { return }
        button.image = MenuBarIconRenderer.image(for: model.iconState)
        // The prototype shades the item while the panel is open, like an open menu.
        button.highlight(model.isPanelOpen)
    }

    @objc private func clicked() {
        model.togglePanel()
    }
}
