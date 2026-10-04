import CoreGraphics

/// One piece of a menu-bar glyph: a filled outline, or a cut that clears what's been drawn under
/// it. In the prototype's 18 × 18 SVG box, y down.
nonisolated struct GlyphLayer: @unchecked Sendable {
    // Unchecked because CGPath isn't marked Sendable; these paths are built once and never mutated.
    let path: CGPath
    var opacity: CGFloat = 1
    var cuts = false
}

/// The glyphs of `design/prototype/MenuBarIcon.dc.html`, as one source for both the menu-bar image
/// (`MenuBarIconRenderer`) and the glyph inside the surfaces (`MenuBarGlyph`). Strokes are turned
/// into filled outlines here and SVG masks into cuts, so both renderers only fill and clear, and
/// draw exactly the same shapes.
enum MenuBarGlyphGeometry {
    /// The SVG's viewBox: the glyph is drawn in an 18 × 18 box and scaled from there.
    nonisolated static let box: CGFloat = 18

    /// The layers for a state, back to front. `.target` draws the `.open` glyph; its highlight is
    /// the renderer's.
    static func layers(for state: MenuBarIconState) -> [GlyphLayer] {
        switch state {
        case .idle:
            closedBox.map { GlyphLayer(path: stroke($0, width: 1.5)) }
        case .open, .target:
            openBox.map { GlyphLayer(path: stroke($0, width: 1.5)) }
        case .zipping:
            // A dashed ring at 55 %, starting at 3 o'clock like an SVG circle's dashes.
            [GlyphLayer(path: stroke(ring.copy(dashingWithPhase: 0, lengths: [2.2, 2.2]), width: 1.6, cap: .butt),
                        opacity: 0.55),
             GlyphLayer(path: stroke(upArrow, width: 1.5))]
        case .progress(let fraction):
            // The track at 30 %, the part sent over it at full strength.
            [GlyphLayer(path: stroke(ring, width: 1.6), opacity: 0.3),
             arc(fraction).map { GlyphLayer(path: stroke($0, width: 1.6, cap: .butt)) },
             GlyphLayer(path: stroke(upArrow, width: 1.5))].compactMap { $0 }
        case .paused(let fraction):
            // Dimmed where it stopped, with pause bars.
            [GlyphLayer(path: stroke(ring, width: 1.6), opacity: 0.25),
             arc(fraction).map { GlyphLayer(path: stroke($0, width: 1.6, cap: .butt), opacity: 0.5) },
             GlyphLayer(path: stroke(pauseBars, width: 1.7))].compactMap { $0 }
        case .done:
            [GlyphLayer(path: circle(x: 9, y: 9, radius: 7.75)),
             GlyphLayer(path: stroke(check, width: 1.8), cuts: true)]
        case .error:
            // The box, with a ring cleared around the badge so the two don't touch, then the
            // badge with its "!" cleared out.
            closedBox.map { GlyphLayer(path: stroke($0, width: 1.5)) } + [
             GlyphLayer(path: circle(x: 14, y: 14, radius: 5.3), cuts: true),
             GlyphLayer(path: circle(x: 14, y: 14, radius: 4)),
             GlyphLayer(path: stroke(line((14, 11.7), (14, 14.1)), width: 1.5), cuts: true),
             GlyphLayer(path: circle(x: 14, y: 16.2, radius: 0.85), cuts: true)]
        }
    }

    // MARK: Shapes, as the SVG's paths

    /// The parcel, as the SVG's three elements: the lid (`<rect x=2 y=3 width=14 height=3.75
    /// rx=1>`), the box under it with rounded bottom corners, and an up arrow inside. They're
    /// separate layers because the SVG's elements are: in a translucent colour, the box's sides
    /// show darker where they overlap the lid, as in the prototype.
    private static let closedBox: [CGPath] = {
        let lid = CGPath(roundedRect: CGRect(x: 2, y: 3, width: 14, height: 3.75), cornerWidth: 1, cornerHeight: 1,
                         transform: nil)
        let box = CGMutablePath()
        box.move(to: CGPoint(x: 3.25, y: 6.75))
        box.addArc(tangent1End: CGPoint(x: 3.25, y: 15.25), tangent2End: CGPoint(x: 5, y: 15.25), radius: 1.75)
        box.addArc(tangent1End: CGPoint(x: 14.75, y: 15.25), tangent2End: CGPoint(x: 14.75, y: 13.5), radius: 1.75)
        box.addLine(to: CGPoint(x: 14.75, y: 6.75))
        let arrow = CGMutablePath()
        arrow.addPath(polyline((9, 13), (9, 9.4)))
        arrow.addPath(polyline((7.2, 11.1), (9, 9.3), (10.8, 11.1)))
        return [lid, box, arrow]
    }()

    /// The open box, wider and without a lid, and an arrow pointing into it.
    private static let openBox: [CGPath] = {
        let box = CGMutablePath()
        box.move(to: CGPoint(x: 2.5, y: 7.5))
        box.addArc(tangent1End: CGPoint(x: 2.5, y: 15.25), tangent2End: CGPoint(x: 4.25, y: 15.25), radius: 1.75)
        box.addArc(tangent1End: CGPoint(x: 15.5, y: 15.25), tangent2End: CGPoint(x: 15.5, y: 13.5), radius: 1.75)
        box.addLine(to: CGPoint(x: 15.5, y: 7.5))
        let arrow = CGMutablePath()
        arrow.addPath(polyline((9, 2.6), (9, 11.2)))
        arrow.addPath(polyline((6.6, 8.8), (9, 11.2), (11.4, 8.8)))
        return [box, arrow]
    }()

    private static let upArrow: CGPath = {
        let path = CGMutablePath()
        path.addPath(polyline((9, 12.1), (9, 6.3)))
        path.addPath(polyline((6.8, 8.5), (9, 6.2), (11.2, 8.5)))
        return path
    }()

    private static let pauseBars: CGPath = {
        let path = CGMutablePath()
        path.addPath(polyline((7.3, 6.6), (7.3, 11.4)))
        path.addPath(polyline((10.7, 6.6), (10.7, 11.4)))
        return path
    }()

    private static let check = polyline((5.6, 9.3), (7.9, 11.6), (12.4, 6.9))

    /// The progress ring's track: a circle of radius 7, from 3 o'clock, clockwise on screen.
    private static let ring: CGPath = {
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 9, y: 9), radius: 7, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        return path
    }()

    /// The filled part of the ring: from 12 o'clock, clockwise on screen, as the SVG's
    /// `rotate(-90)` and `stroke-dasharray`. Nil when there's nothing to draw.
    private static func arc(_ fraction: Double) -> CGPath? {
        let fraction = min(max(fraction, 0), 1)
        guard fraction > 0 else { return nil }
        let path = CGMutablePath()
        let start = -CGFloat.pi / 2
        path.addArc(center: CGPoint(x: 9, y: 9), radius: 7, startAngle: start,
                    endAngle: start + 2 * .pi * fraction, clockwise: false)
        return path
    }

    // MARK: Helpers

    private static func polyline(_ points: (CGFloat, CGFloat)...) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        return path
    }

    private static func line(_ from: (CGFloat, CGFloat), _ to: (CGFloat, CGFloat)) -> CGPath {
        polyline(from, to)
    }

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }

    /// The outline of a stroke, with the SVG's round caps and joins unless told otherwise.
    private static func stroke(_ path: CGPath, width: CGFloat, cap: CGLineCap = .round) -> CGPath {
        path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: 4)
    }
}
