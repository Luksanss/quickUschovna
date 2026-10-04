import AppKit
import SwiftUI

/// How a surface's background is drawn.
enum SurfaceBackdrop {
    /// The window server's blur of what's behind the window, tinted to `--mat`. For real windows.
    case material
    /// `--mat` alone. For rendering offscreen (the Debug gallery), where the window server's blur
    /// doesn't render.
    case flat
}

/// How a surface comes in when it's shown: the prototype's two keyframes, both 120 ms ease-out.
enum SurfaceEntrance {
    /// `qsIn`: fades in while sliding down 4 pt. The bubble and the panel.
    case slideIn
    /// `qsFade`: fades in. The drop zone, which shouldn't draw the eye to itself.
    case fade
}

extension EnvironmentValues {
    @Entry var surfaceBackdrop: SurfaceBackdrop = .material
    /// Off for offscreen renders, which never get the `onAppear` that would play the entrance.
    @Entry var playsSurfaceEntrance = true
    /// The surface has come in, or is coming in. Before that it's transparent, and SwiftUI won't
    /// give focus to a field in it.
    @Entry var isSurfaceShown = true
}

extension View {
    /// Puts content on a surface: `SurfaceMetrics.width` wide, its padding inside, the material,
    /// the hairlines and the shadow, and the shadow's room around it (`SurfaceMetrics.shadowInsets`),
    /// so a transparent window sized to the view's fitting size shows all of it.
    func surfaceChrome(padding: EdgeInsets, entrance: SurfaceEntrance) -> some View {
        surfaceBody(padding: padding).surfaceWindow(entrance: entrance)
    }

    /// The surface itself: the content in its padding, `SurfaceMetrics.width` wide, on the material
    /// with its hairlines. Hover and click handlers attached to this cover the surface exactly.
    /// `surfaceWindow` then adds the shadow and the room for it.
    func surfaceBody(padding: EdgeInsets) -> some View {
        modifier(SurfaceBody(padding: padding))
    }

    /// The shadow, the entrance and the shadow's room, around a `surfaceBody`.
    func surfaceWindow(entrance: SurfaceEntrance) -> some View {
        modifier(SurfaceShell(entrance: entrance))
    }
}

private let surfaceShape = RoundedRectangle(cornerRadius: SurfaceMetrics.cornerRadius, style: .circular)

private struct SurfaceBody: ViewModifier {
    let padding: EdgeInsets

    @Environment(\.surfaceTokens) private var tokens
    @Environment(\.surfaceBackdrop) private var backdrop

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(width: SurfaceMetrics.width, alignment: .leading)
            .background { background }
            .overlay { hairlines }
            .contentShape(surfaceShape)
    }

    @ViewBuilder private var background: some View {
        switch backdrop {
        case .material:
            ZStack {
                BehindWindowBlur(cornerRadius: SurfaceMetrics.cornerRadius)
                surfaceShape.fill(tokens.material)
            }
        case .flat:
            surfaceShape.fill(tokens.material)
        }
    }

    /// `0 0 0 .5px` outside the edge, and in dark mode `inset 0 0 0 .5px` inside it.
    private var hairlines: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SurfaceMetrics.cornerRadius + 0.5, style: .circular)
                .strokeBorder(tokens.outline, lineWidth: 0.5)
                .padding(-0.5)
            if let highlight = tokens.innerHighlight {
                surfaceShape.strokeBorder(highlight, lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SurfaceShell: ViewModifier {
    let entrance: SurfaceEntrance

    @Environment(\.surfaceTokens) private var tokens
    @Environment(\.playsSurfaceEntrance) private var playsEntrance
    @State private var hasEntered = false

    func body(content: Content) -> some View {
        let isIn = hasEntered || !playsEntrance
        content
            .environment(\.isSurfaceShown, isIn)
            .background {
                SurfaceShadow(color: NSColor(tokens.shadow))
                    .padding(-SurfaceShadow.reach)
                    .allowsHitTesting(false)
            }
            .opacity(isIn ? 1 : 0)
            .offset(y: isIn || entrance == .fade ? 0 : -4)
            .padding(EdgeInsets(top: SurfaceMetrics.shadowInsets.top,
                                leading: SurfaceMetrics.shadowInsets.leading,
                                bottom: SurfaceMetrics.shadowInsets.bottom,
                                trailing: SurfaceMetrics.shadowInsets.trailing))
            .onAppear {
                guard playsEntrance else { return }
                withAnimation(.easeOut(duration: 0.12)) { hasEntered = true }
            }
    }
}

/// `0 12px 32px` in the shadow's colour, painted only outside the surface, as CSS paints a
/// box-shadow, so it doesn't darken the translucent material. Drawn by AppKit rather than with
/// SwiftUI's blur, which doesn't render offscreen for the Debug gallery. It's laid out `reach`
/// bigger than the surface on every side, to have room to draw in.
private struct SurfaceShadow: NSViewRepresentable {
    static let reach: CGFloat = 64

    let color: NSColor

    func makeNSView(context: Context) -> ShadowView {
        ShadowView()
    }

    func updateNSView(_ view: ShadowView, context: Context) {
        view.color = color
    }

    final class ShadowView: NSView {
        var color = NSColor.clear {
            didSet { if color != oldValue { needsDisplay = true } }
        }

        override var isFlipped: Bool { true }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsDisplay = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            let surface = bounds.insetBy(dx: SurfaceShadow.reach, dy: SurfaceShadow.reach)
            let radius = SurfaceMetrics.cornerRadius
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(roundedRect: surface, xRadius: radius, yRadius: radius))
            outside.windingRule = .evenOdd
            outside.addClip()
            // The shape that casts the shadow sits 12 pt lower (this view is flipped) and a view's
            // width to the left, out of sight; the shadow's offset brings it back across. A
            // vertical offset would do instead, but which way it points depends on the context's
            // flipping, which differs between a window and an offscreen render.
            let away = bounds.width
            let shadow = NSShadow()
            shadow.shadowColor = color
            // AppKit's blur radius is CSS's: twice the Gaussian's standard deviation.
            shadow.shadowBlurRadius = 32
            shadow.shadowOffset = NSSize(width: away, height: 0)
            shadow.set()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: surface.offsetBy(dx: -away, dy: 12), xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// The window server's blur of whatever is behind the window, clipped to the surface's rounded
/// rectangle. The clip is a mask image because a behind-window blur ignores layer masks.
///
/// `--mat` goes over it, so it shows through only as much as the prototype's backdrop does, 20 %
/// in light mode and 24 % in dark. Under that tint `.hudWindow`, the most see-through material,
/// comes closest to the prototype: measured on screen over the prototype's wallpaper, within 1
/// (of 255) of its colour in dark mode and within 5 in light, where the other materials are 7 to
/// 20 off in light.
private struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A stretchable rounded rectangle: only its corners keep their size. Nonisolated, because
    /// AppKit may draw the image on any thread.
    private nonisolated static func mask(cornerRadius radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
