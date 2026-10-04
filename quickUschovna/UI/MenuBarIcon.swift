import AppKit
import SwiftUI

/// The menu-bar icon's image for each state (`design/prototype/MenuBarIcon.dc.html`), for the
/// `NSStatusItem`'s button. Every state is an 18 pt template image that macOS tints for the menu
/// bar, except `.target`: the prototype draws it on an accent highlight that reaches 5 pt past the
/// glyph on either side and 2 pt above and below (`padding:2px 5px; margin:-2px -5px`), so that
/// image is 28 × 22 pt, in colour, with the glyph in white. The images draw on demand, so they're
/// sharp at any scale.
enum MenuBarIconRenderer {
    static func image(for state: MenuBarIconState) -> NSImage {
        let painter = GlyphPainter(layers: MenuBarGlyphGeometry.layers(for: state))
        let image: NSImage
        if state == .target {
            image = NSImage(size: GlyphPainter.targetSize, flipped: true, drawingHandler: painter.drawOnHighlight)
        } else {
            let side = MenuBarGlyphGeometry.box
            image = NSImage(size: NSSize(width: side, height: side), flipped: true, drawingHandler: painter.drawTemplate)
            image.isTemplate = true
        }
        image.accessibilityDescription = "quickUschovna"
        return image
    }
}

/// Draws glyph layers into AppKit's current context. Nonisolated, because AppKit may draw an
/// image on any thread.
private nonisolated final class GlyphPainter: Sendable {
    static let targetSize = NSSize(width: 28, height: 22)
    private static let highlightRadius: CGFloat = 5

    private let layers: [GlyphLayer]

    init(layers: [GlyphLayer]) {
        self.layers = layers
    }

    /// Black at each layer's opacity, which is all a template image keeps.
    func drawTemplate(_ rect: NSRect) -> Bool {
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.scaleBy(x: rect.width / MenuBarGlyphGeometry.box, y: rect.height / MenuBarGlyphGeometry.box)
        fill(in: context, color: .black)
        return true
    }

    /// The accent highlight, then the glyph in white in its middle.
    func drawOnHighlight(_ rect: NSRect) -> Bool {
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.scaleBy(x: rect.width / Self.targetSize.width, y: rect.height / Self.targetSize.height)
        let highlight = CGRect(origin: .zero, size: Self.targetSize)
        context.addPath(CGPath(roundedRect: highlight, cornerWidth: Self.highlightRadius,
                               cornerHeight: Self.highlightRadius, transform: nil))
        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.fillPath()
        context.translateBy(x: (highlight.width - MenuBarGlyphGeometry.box) / 2,
                            y: (highlight.height - MenuBarGlyphGeometry.box) / 2)
        fill(in: context, color: .white)
        return true
    }

    /// In a transparency layer of its own, so the cuts clear only the glyph.
    private func fill(in context: CGContext, color: NSColor) {
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for layer in layers {
            context.addPath(layer.path)
            if layer.cuts {
                context.setBlendMode(.clear)
            } else {
                context.setBlendMode(.normal)
                context.setFillColor(color.withAlphaComponent(layer.opacity).cgColor)
            }
            context.fillPath()
        }
        context.endTransparencyLayer()
    }
}

/// The icon's glyph inside the surfaces, in the foreground style: 22 pt in the drop zone, 16 pt in
/// the email bubble. The same shapes as the menu-bar image.
struct MenuBarGlyph: View {
    let state: MenuBarIconState
    let size: CGFloat

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        let layers = MenuBarGlyphGeometry.layers(for: state)
        if state == .target {
            // The highlight scales with the glyph, from its 18 pt proportions.
            let scale = size / MenuBarGlyphGeometry.box
            GlyphCanvas(layers: layers, size: size)
                .foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 5 * scale, style: .circular)
                        .fill(tokens.accent)
                        .padding(.horizontal, -5 * scale)
                        .padding(.vertical, -2 * scale)
                }
        } else {
            GlyphCanvas(layers: layers, size: size)
        }
    }
}

private struct GlyphCanvas: View {
    let layers: [GlyphLayer]
    let size: CGFloat

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: size / MenuBarGlyphGeometry.box, y: size / MenuBarGlyphGeometry.box)
            // A layer of its own, so the cuts clear only the glyph.
            context.drawLayer { glyph in
                for layer in layers {
                    var piece = glyph
                    if layer.cuts {
                        piece.blendMode = .destinationOut
                        piece.fill(Path(layer.path), with: .color(.black))
                    } else {
                        piece.opacity = layer.opacity
                        piece.fill(Path(layer.path), with: .foreground)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
