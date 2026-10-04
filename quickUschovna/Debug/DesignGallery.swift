#if DEBUG
import AppKit
import SwiftUI

/// Every surface state and icon state, rendered to PNGs at 2× for comparing with the prototype
/// (`design/prototype/quickUschovna v1.dc.html`). Debug builds only.
///
/// `main.swift` calls `renderIfRequested()` before the app runs, and exits when it returns true.
/// Launch with `--render-gallery <directory>`, plus `-AppleLocale en_US` for the prototype's
/// English sizes and dates: it writes `<state>-light.png` and `<state>-dark.png` for each
/// `GalleryState`, and the icon sheets. Each surface is drawn over the prototype's wallpaper at the
/// spot where the prototype's captures are taken (x 592, y 30 on its 1280 × 800 desktop), with its
/// shadow room, so the two line up. The window server's blur doesn't render offscreen, so the
/// material is drawn as its `--mat` colour over the wallpaper.
enum DesignGallery {
    /// Renders the gallery if the arguments ask for it, and says whether they did.
    static func renderIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let flag = arguments.firstIndex(of: "--render-gallery"), arguments.indices.contains(flag + 1) else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try render(to: directory)
        } catch {
            FileHandle.standardError.write(Data("Gallery: \(error)\n".utf8))
        }
        return true
    }

    static func render(to directory: URL) throws {
        for state in GalleryState.all {
            for scheme in [ColorScheme.light, .dark] {
                let model = AppModel()
                state.stage(model)
                let canvas = SurfaceCanvas(scheme: scheme) { surface(state.surface, model: model) }
                try write(canvas, scheme: scheme, to: directory.appending(path: "\(state.name)-\(scheme.name).png"))
            }
        }
        try write(IconSheet(), scheme: .light, to: directory.appending(path: "icons.png"))
        try write(MenuBarImageSheet(), scheme: .light, to: directory.appending(path: "icons-menubar-enlarged.png"))
    }

    @ViewBuilder private static func surface(_ surface: GalleryState.Surface, model: AppModel) -> some View {
        switch surface {
        case .dropZone: DropZoneView(model: model)
        case .bubble: BubbleView(model: model)
        case .panel: PanelView(model: model)
        }
    }

    /// Renders a view at its fitting size into a 2× sRGB PNG, in a window that's never shown, so
    /// AppKit-backed controls such as text fields draw too.
    private static func write(_ view: some View, scheme: ColorScheme, to url: URL) throws {
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, scheme)
            .environment(\.surfaceBackdrop, .flat)
            .environment(\.playsSurfaceEntrance, false))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .retagging(with: .sRGB) else {
            throw GalleryError.bitmap(url.lastPathComponent)
        }
        bitmap.size = size
        // Without font smoothing, as text renders into a window's transparent layers, and as the
        // prototype's `-webkit-font-smoothing: antialiased` renders it.
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw GalleryError.bitmap(url.lastPathComponent)
        }
        context.cgContext.setAllowsFontSmoothing(false)
        context.cgContext.setShouldSmoothFonts(false)
        host.displayIgnoringOpacity(host.bounds, in: context)
        context.flushGraphics()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.bitmap(url.lastPathComponent)
        }
        try png.write(to: url)
        window.contentView = nil
    }

    private enum GalleryError: Error {
        case bitmap(String)
    }
}

private extension ColorScheme {
    var name: String { self == .dark ? "dark" : "light" }
}

// MARK: - Backdrop

/// A surface over the prototype's wallpaper, cut to the surface and its shadow room. Under the
/// surface, the wallpaper is saturated 1.8 times, as the prototype's `backdrop-filter` does before
/// `--mat` goes over it; its blur makes no difference to a gradient this smooth.
private struct SurfaceCanvas<Surface: View>: View {
    let scheme: ColorScheme
    @ViewBuilder let surface: Surface

    private static var insets: (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        SurfaceMetrics.shadowInsets
    }

    /// Where the canvas's top-left corner is on the prototype's desktop: the surface's spot
    /// (x 592, y 30) less the shadow room.
    private static var origin: CGPoint {
        CGPoint(x: 592 - insets.leading, y: 30 - insets.top)
    }

    var body: some View {
        surface
            .background(alignment: .topLeading) {
                GeometryReader { proxy in
                    let surface = CGRect(x: Self.insets.leading, y: Self.insets.top, width: SurfaceMetrics.width,
                                         height: proxy.size.height - Self.insets.top - Self.insets.bottom)
                    ZStack(alignment: .topLeading) {
                        wallpaper(saturation: 1)
                        wallpaper(saturation: 1.8)
                            .mask(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: SurfaceMetrics.cornerRadius, style: .circular)
                                    .frame(width: surface.width, height: surface.height)
                                    .offset(x: surface.minX, y: surface.minY)
                            }
                    }
                }
            }
            .clipped()
    }

    private func wallpaper(saturation: Double) -> some View {
        Wallpaper(isDark: scheme == .dark, saturation: saturation)
            .frame(width: Wallpaper.size.width, height: Wallpaper.size.height)
            .offset(x: -Self.origin.x, y: -Self.origin.y)
    }
}

/// The prototype desktop's `--wall`: a 165° CSS gradient over 1280 × 800, optionally through CSS's
/// `saturate()`.
private struct Wallpaper: View {
    static let size = CGSize(width: 1280, height: 800)

    let isDark: Bool
    var saturation = 1.0

    var body: some View {
        let stops: [(UInt32, Double)] = isDark
            ? [(0x2C3541, 0), (0x1D242D, 0.6), (0x141A21, 1)]
            : [(0xC7D3DC, 0), (0xA7B9C7, 0.55), (0x8EA3B4, 1)]
        let (start, end) = Self.endpoints(degrees: 165)
        LinearGradient(stops: stops.map { Gradient.Stop(color: Self.saturate($0.0, by: saturation), location: $0.1) },
                       startPoint: start, endPoint: end)
    }

    /// CSS's gradient line: through the centre at the angle (0° up, clockwise), long enough that
    /// the corners get the end colours.
    private static func endpoints(degrees: Double) -> (UnitPoint, UnitPoint) {
        let angle = degrees * .pi / 180
        let direction = CGPoint(x: sin(angle), y: -cos(angle))
        let length = abs(size.width * direction.x) + abs(size.height * direction.y)
        let half = CGPoint(x: direction.x * length / 2 / size.width, y: direction.y * length / 2 / size.height)
        return (UnitPoint(x: 0.5 - half.x, y: 0.5 - half.y), UnitPoint(x: 0.5 + half.x, y: 0.5 + half.y))
    }

    /// The Filter Effects `saturate()` matrix, in sRGB as Chrome applies it. It's linear, so
    /// saturating the stops saturates the whole gradient.
    private static func saturate(_ hex: UInt32, by s: Double) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return Color(.sRGB,
                     red: clamp((0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * b),
                     green: clamp((0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * b),
                     blue: clamp((0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * b))
    }
}

// MARK: - Icons

private let iconStates: [MenuBarIconState] = [.idle, .open, .target, .zipping, .progress(0.35), .paused(0.6), .done, .error]

/// As the prototype's icon captures: each state at 72 pt in the surfaces' glyph, then the
/// menu-bar image at 18 pt on a light and a dark menu bar, tinted as macOS tints a template.
private struct IconSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(iconStates.indices, id: \.self) { index in
                    MenuBarGlyph(state: iconStates[index], size: 72)
                        .foregroundStyle(Color(0x1D1D1F))
                        .frame(width: 96, height: 96)
                        .background(Color(0xF4F4F6))
                }
            }
            menuBar(background: Color(0xDDE3E9), tint: .black)
            menuBar(background: Color(0x22282F), tint: .white)
        }
    }

    private func menuBar(background: Color, tint: Color) -> some View {
        HStack(spacing: 0) {
            ForEach(iconStates.indices, id: \.self) { index in
                MenuBarImage(state: iconStates[index])
                    .foregroundStyle(tint)
                    .frame(width: 96, height: 24)
                    .background(background)
            }
        }
    }
}

/// The menu-bar images drawn at 4×, to check that they stay sharp.
private struct MenuBarImageSheet: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(iconStates.indices, id: \.self) { index in
                MenuBarImage(state: iconStates[index], scale: 4)
                    .foregroundStyle(Color(0x1D1D1F))
                    .frame(width: 128, height: 96)
                    .background(Color(0xF4F4F6))
            }
        }
    }
}

/// `MenuBarIconRenderer`'s image, tinted like a template when it is one.
private struct MenuBarImage: View {
    let state: MenuBarIconState
    var scale: CGFloat = 1

    var body: some View {
        let image = MenuBarIconRenderer.image(for: state)
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
    }
}
#endif
