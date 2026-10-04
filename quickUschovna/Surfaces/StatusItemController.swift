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
            drop.onHover = { [weak model] over in model?.dragOverIcon(over) }
            drop.onDrop = { [weak model] urls in model?.send(urls) }
            drop.attach(to: window)
        }
        observe { [weak self] in self?.update() }
    }

    /// Where the surfaces hang, in screen coordinates: their left edge, 8 pt left of the item and
    /// kept 8 pt inside the screen, their top, 6 pt under the menu bar, and the item's screen.
    var surfaceAnchor: (left: CGFloat, top: CGFloat, screen: NSRect)? {
        guard let button = item.button, let window = button.window,
              let screen = window.screen?.frame else { return nil }
        let itemFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let lowest = screen.minX + SurfaceMetrics.screenMargin
        let highest = screen.maxX - SurfaceMetrics.screenMargin - SurfaceMetrics.width
        let left = min(max(itemFrame.minX - SurfaceMetrics.leadingOffset, lowest), highest)
        return (left, window.frame.minY - SurfaceMetrics.gapBelowMenuBar, screen)
    }

    /// Where a file drag opens the drop zone before it reaches the item: the zone's place, widened
    /// by `SurfaceMetrics.dropZoneApproach` to its sides and below, and the menu bar above it.
    var dropZoneApproach: NSRect? {
        guard let anchor = surfaceAnchor else { return nil }
        let margin = SurfaceMetrics.dropZoneApproach
        let bottom = anchor.top - SurfaceMetrics.dropZoneHeight - margin
        return NSRect(x: anchor.left - margin, y: bottom,
                      width: SurfaceMetrics.width + 2 * margin, height: anchor.screen.maxY - bottom)
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
