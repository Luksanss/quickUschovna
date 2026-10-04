import SwiftUI

/// A name whose end never truncates (`Format.splitName`): the head gets the ellipsis, while the
/// tail, with the extension, stays whole, followed by `suffix` (" · 2.4 GB"), which stays whole too.
/// A truncated head takes all the room the tail leaves, as the prototype's shrinking flex item
/// does, so its ellipsis can stand a little apart from the tail.
struct SplitName: View {
    let name: String
    var suffix = ""

    var body: some View {
        let parts = Format.splitName(name)
        let tail = Text(parts.tail + suffix).lineLimit(1).fixedSize()
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text(parts.head).lineLimit(1).fixedSize()
                tail
            }
            HStack(spacing: 0) {
                Text(parts.head)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tail
            }
        }
    }
}

/// The prototype's small inline icons, from their SVG paths: stroked in viewBox units and scaled
/// with the frame, as the SVG is.
nonisolated struct SurfaceIcon: Shape {
    enum Kind {
        /// The "Link copied" badge's check (viewBox 16).
        case check
        /// The "!" of the warning and error badges (viewBox 16).
        case exclamation
        /// ↗, "Open in browser" (viewBox 14).
        case openArrow
        /// ×, "Cancel" (viewBox 10).
        case cross
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    func path(in rect: CGRect) -> Path {
        let (viewBox, outline) = Self.outline(of: kind)
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / viewBox, y: rect.height / viewBox)
        return Path(outline).applying(transform)
    }

    private static func outline(of kind: Kind) -> (viewBox: CGFloat, path: CGPath) {
        switch kind {
        case .check:
            return (16, stroke([(3.5, 8.4), (6.5, 11.4), (12.5, 4.8)], width: 2))
        case .exclamation:
            let path = CGMutablePath()
            path.addPath(stroke([(8, 3.6), (8, 8.8)], width: 2))
            path.addEllipse(in: CGRect(x: 8 - 1.1, y: 12.1 - 1.1, width: 2.2, height: 2.2))
            return (16, path)
        case .openArrow:
            let path = CGMutablePath()
            path.addPath(stroke([(4.5, 2.5), (11.5, 2.5), (11.5, 9.5)], width: 1.6))
            path.addPath(stroke([(11.5, 2.5), (2.5, 11.5)], width: 1.6))
            return (14, path)
        case .cross:
            let path = CGMutablePath()
            path.addPath(stroke([(2, 2), (8, 8)], width: 1.6))
            path.addPath(stroke([(8, 2), (2, 8)], width: 1.6))
            return (10, path)
        }
    }

    private static func stroke(_ points: [(CGFloat, CGFloat)], width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }
}

/// The 28 pt round badge at the start of each bubble.
struct BubbleBadge<Glyph: View>: View {
    let color: Color
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay { glyph }
    }
}

/// The 24 pt buttons: Try Again, and Cancel and Quit under "Quit while sending?". Prominent ones
/// are accent with 12 pt semibold white text; the others `--fill` with regular text.
struct SurfaceButton: View {
    let title: LocalizedStringKey
    var isProminent = true
    let action: () -> Void

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        Button(action: action) {
            Text(title)
                .surfaceFont(12, isProminent ? .semibold : .regular)
                .foregroundStyle(isProminent ? .white : tokens.fg)
                .padding(.horizontal, 12)
                // Centred, the 15 pt line would sit 4.5 pt down; Chrome paints it at 5.
                .padding(.top, 5)
                .padding(.bottom, 4)
                .background(isProminent ? tokens.accent : tokens.fill,
                            in: RoundedRectangle(cornerRadius: 6, style: .circular))
        }
        .buttonStyle(BareButtonStyle())
    }
}

/// The line between the panel's sections: 1 pt of `--sep`, 10 pt in from the sides, 4 pt above and
/// below.
struct SurfaceSeparator: View {
    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        Rectangle()
            .fill(tokens.separator)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

/// The prototype's email field: `--field`, a hairline ring and a 3 pt accent ring at 40 %. The
/// rings always show, because the field is only on screen while it's being typed in. It takes
/// focus as soon as its surface comes in, which needs its window to be key.
struct EmailField: View {
    @Binding var text: String
    var placeholder = ""
    let height: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    var alignment: TextAlignment = .leading
    let onSubmit: () -> Void
    var onFocusLost: (() -> Void)?

    @Environment(\.surfaceTokens) private var tokens
    @Environment(\.isSurfaceShown) private var isSurfaceShown
    @FocusState private var isFocused: Bool

    /// Chrome's placeholder grey, the same in both appearances.
    private static let placeholderColor = Color(0x757575)

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(tokens.fieldText)
            .opacity(tokens.fieldTextOpacity)
            .multilineTextAlignment(alignment)
            .autocorrectionDisabled()
            .focusEffectDisabled()
            .accessibilityLabel("Sender email")
            .focused($isFocused)
            .onSubmit(onSubmit)
            .background(alignment: alignment == .trailing ? .trailing : .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Self.placeholderColor)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(tokens.field, in: RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
            .overlay { rings.allowsHitTesting(false) }
            // Once the surface is in: a field in a transparent view can't take focus.
            .onChange(of: isSurfaceShown, initial: true) { _, shown in
                if shown { isFocused = true }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { onFocusLost?() }
            }
    }

    /// `0 0 0 .5px var(--fg3), 0 0 0 3px` accent at 40 %: the hairline is drawn over the wide ring.
    private var rings: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius + 3, style: .circular)
                .strokeBorder(tokens.accent.opacity(0.4), lineWidth: 3)
                .padding(-3)
            RoundedRectangle(cornerRadius: cornerRadius + 0.5, style: .circular)
                .strokeBorder(tokens.fg3, lineWidth: 0.5)
                .padding(-0.5)
        }
    }
}

/// The Launch at Login switch: a 26 × 15 pt track, accent when on and `--fill` when off, with a
/// 12 pt white knob.
struct SurfaceSwitch: View {
    let isOn: Bool

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        Capsule()
            .fill(isOn ? tokens.accent : tokens.fill)
            .frame(width: 26, height: 15)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 0.75, x: 0, y: 0.5)
                    .offset(x: isOn ? 12.5 : 1.5, y: 1.5)
            }
    }
}
