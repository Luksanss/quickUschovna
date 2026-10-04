import AppKit
import SwiftUI

// Placeholders so the scaffold builds. The real views replace this file, matching
// `design/prototype/quickUschovna v1.dc.html` one to one.

/// The menu-bar icon's image for each state, drawn at 18 pt. A template image except `.target`,
/// which carries its own accent highlight.
enum MenuBarIconRenderer {
    static func image(for state: MenuBarIconState) -> NSImage {
        let image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "quickUschovna") ?? NSImage()
        image.isTemplate = true
        return image
    }
}

/// The icon's glyph inside the surfaces: 22 pt in the drop zone, 16 pt in the email bubble.
struct MenuBarGlyph: View {
    let state: MenuBarIconState
    let size: CGFloat

    var body: some View {
        Image(systemName: "shippingbox").frame(width: size, height: size)
    }
}

/// The bubble under the icon, including its chrome and shadow room (`SurfaceMetrics`).
struct BubbleView: View {
    let model: AppModel

    var body: some View {
        Text("Bubble").frame(width: SurfaceMetrics.width)
    }
}

/// The panel that opens on a click on the icon, including its chrome and shadow room.
struct PanelView: View {
    let model: AppModel

    var body: some View {
        Text("Panel").frame(width: SurfaceMetrics.width)
    }
}

/// The drop zone that opens under the icon during a file drag, including its chrome and shadow room.
struct DropZoneView: View {
    let model: AppModel

    var body: some View {
        Text("Drop here to send").frame(width: SurfaceMetrics.width, height: SurfaceMetrics.dropZoneHeight)
    }
}
