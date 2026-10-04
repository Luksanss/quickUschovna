import Foundation

/// Where and how big the surfaces that hang from the icon are: the drop zone, the bubble and the
/// panel. From the prototype, whose menu bar is 24 pt tall and puts every surface at top 30, left
/// `iconLeft - 8`, clamped 8 pt inside the screen.
enum SurfaceMetrics {
    static let width: CGFloat = 300
    static let dropZoneHeight: CGFloat = 88
    static let cornerRadius: CGFloat = 14
    /// From the bottom of the menu bar to the top of a surface.
    static let gapBelowMenuBar: CGFloat = 6
    /// A surface starts this far left of the menu-bar item's left edge.
    static let leadingOffset: CGFloat = 8
    /// The closest a surface gets to the screen's left or right edge.
    static let screenMargin: CGFloat = 8
    /// Room around a surface inside its window for the shadow
    /// (`0 12px 32px rgba(0,0,0,.2)`), so the window can stay transparent there.
    static let shadowInsets = (top: CGFloat(24), leading: CGFloat(36), bottom: CGFloat(48), trailing: CGFloat(36))
}
