import AppKit
import SwiftUI

// Placeholders so the scaffold builds. The real views replace this file, matching
// `design/prototype/quickUschovna v1.dc.html` one to one.

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
