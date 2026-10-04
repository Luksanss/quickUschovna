import SwiftUI

/// The drop zone that fades in under the icon while files are dragged anywhere on screen
/// (`model.drag`), including its chrome and shadow room. 300 × 88 pt: a dashed target inside 6 pt
/// of padding, which turns accent while the drag is over it.
struct DropZoneView: View {
    let model: AppModel

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        let drag = model.drag ?? DragSummary(label: "", bytes: nil)
        let tint = drag.isOver ? tokens.accent : tokens.fg2
        VStack(spacing: 4) {
            // The prototype's glyph sits in a 25 pt line box: 22 pt of glyph on the text's baseline.
            MenuBarGlyph(state: drag.isOver ? .open : .idle, size: 22)
                .frame(height: 25, alignment: .top)
            Text(drag.isOver ? "Release to send" : "Drop here to send")
                .surfaceFont(13, .semibold)
            CappedLine(text: Self.subline(for: drag), maxWidth: 260)
                .surfaceFont(11)
                .foregroundStyle(drag.isTooBig ? tokens.orange : tokens.fg2)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(drag.isOver ? tokens.accent.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .circular))
        .overlay { DashedBorder(color: drag.isOver ? tokens.accent : tokens.fg3) }
        .frame(height: SurfaceMetrics.dropZoneHeight - 12)
        .surfaceChrome(padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), entrance: .fade)
    }

    /// "report.mov · 2.4 GB", or "45 GB, over the 30 GB limit", or just the label while folders
    /// are still being measured.
    private static func subline(for drag: DragSummary) -> String {
        guard let bytes = drag.bytes else { return drag.label }
        if drag.isTooBig {
            return "\(Format.size(bytes)), over the \(Format.size(Limits.freePackageBytes)) limit"
        }
        return "\(drag.label) · \(Format.size(bytes))"
    }
}

/// One line of text, centred, as wide as it needs up to `maxWidth`. Past that it fills
/// `maxWidth` and truncates at its end, as a CSS box with `max-width` and an ellipsis does: a
/// truncated SwiftUI text would shrink to its last whole character and sit off-centre.
private struct CappedLine: View {
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text).lineLimit(1).fixedSize()
            Text(text).lineLimit(1).truncationMode(.tail).frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth)
    }
}

/// CSS's `1.5px dashed` border with a 9 pt radius, as Chrome draws it: 3 pt dashes and 2 pt gaps,
/// the pattern starting afresh on each side and running on round the corner after it. The long
/// sides start with a dash; the short ones 1.55 pt in.
private struct DashedBorder: View {
    let color: Color

    private static let width: CGFloat = 1.5
    private static let radius: CGFloat = 9
    private static let shortSideInset: CGFloat = 1.55

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size).insetBy(dx: Self.width / 2, dy: Self.width / 2)
            Self.outline(of: rect, radius: Self.radius - Self.width / 2)
                .stroke(color, style: StrokeStyle(lineWidth: Self.width, lineCap: .butt, dash: [3, 2]))
        }
    }

    /// One run per side, clockwise from the top, as each run starts the dash pattern afresh.
    private static func outline(of rect: CGRect, radius r: CGFloat) -> Path {
        let inset = shortSideInset
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + r + inset))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        path.move(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - r - inset))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        return path
    }
}
