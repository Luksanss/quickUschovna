import AppKit
import SwiftUI

/// The prototype's colour tokens (`THEMES` in `design/prototype/quickUschovna v1.dc.html`), read
/// from the environment as `\.surfaceTokens`, so they follow the view's appearance.
struct SurfaceTokens {
    /// `--fg`: text.
    let fg: Color
    /// `--fg2`: secondary text, such as sizes, dates and section headers.
    let fg2: Color
    /// `--fg3`: the idle drop zone's border, field rings, and the zipping and paused bars.
    let fg3: Color
    /// `--sep`: the lines between the panel's sections.
    let separator: Color
    /// `--hover`: a panel row under the pointer.
    let hover: Color
    /// `--fill`: progress tracks, small buttons, the email badge, the switch when off.
    let fill: Color
    /// `--field`: a text field's background.
    let field: Color
    /// `--red`: errors in text.
    let red: Color
    /// `--orange`: warnings in text, such as "expires tomorrow" and "over the 30 GB limit".
    let orange: Color
    /// `--mat`: the surface's background, over the blur of what's behind it.
    let material: Color
    /// From `--shadow`: the drop shadow's colour, the hairline just outside the surface, and in
    /// dark mode a hairline highlight just inside it.
    let shadow: Color
    let outline: Color
    let innerHighlight: Color?

    /// `--acc`: the accent colour the user picked in System Settings, which the prototype's
    /// swatches mirror. On macOS 27 the system's blue is #007AFF in both appearances, where the
    /// prototype's dark variant is #0A84FF.
    var accent: Color { Color(nsColor: .controlAccentColor) }

    /// `--fg` as an opaque colour and an opacity, for text fields, whose text AppKit draws
    /// opaque whatever the colour's alpha.
    let fieldText: Color
    let fieldTextOpacity: Double

    static let light = SurfaceTokens(
        fg: Color(0x000000, 0.86), fg2: Color(0x000000, 0.56), fg3: Color(0x000000, 0.3),
        separator: Color(0x000000, 0.1), hover: Color(0x000000, 0.06), fill: Color(0x000000, 0.09),
        field: Color(0xFFFFFF), red: Color(0xD92D20), orange: Color(0xB86200),
        material: Color(0xF0F0F3, 0.8),
        shadow: Color(0x000000, 0.2), outline: Color(0x000000, 0.16), innerHighlight: nil,
        fieldText: .black, fieldTextOpacity: 0.86)

    static let dark = SurfaceTokens(
        fg: Color(0xFFFFFF, 0.88), fg2: Color(0xFFFFFF, 0.58), fg3: Color(0xFFFFFF, 0.3),
        separator: Color(0xFFFFFF, 0.1), hover: Color(0xFFFFFF, 0.08), fill: Color(0xFFFFFF, 0.14),
        field: Color(0x000000, 0.28), red: Color(0xFF6B5E), orange: Color(0xFFB340),
        material: Color(0x28282C, 0.76),
        shadow: Color(0x000000, 0.5), outline: Color(0x000000, 0.7), innerHighlight: Color(0xFFFFFF, 0.14),
        fieldText: .white, fieldTextOpacity: 0.88)

    /// The bubble's "too big" and "not answering" badges, the same in both appearances.
    static let warningBadge = Color(0xFF9500)
    static let errorBadge = Color(0xFF3B30)
}

extension EnvironmentValues {
    var surfaceTokens: SurfaceTokens { colorScheme == .dark ? .dark : .light }
}

extension Color {
    /// An sRGB colour from a CSS hex value, as the prototype writes them.
    init(_ hex: UInt32, _ opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension View {
    /// The system font at one of the prototype's sizes, in the line box Chrome gives SF Pro at
    /// `line-height: normal`. SwiftUI's own line heights run up to a point taller, which would add
    /// up down the panel, so every line of text sits in the prototype's box instead.
    func surfaceFont(_ size: CGFloat, _ weight: Font.Weight = .regular, lineHeight: CGFloat? = nil) -> some View {
        font(.system(size: size, weight: weight))
            .offset(y: SurfaceLine.baselineShift(size))
            .frame(height: lineHeight ?? SurfaceLine.height(size))
    }
}

enum SurfaceLine {
    /// Chrome's `line-height: normal` for SF Pro: 16 pt at 13 px, 15 at 12, 13 at 11.
    static func height(_ size: CGFloat) -> CGFloat {
        switch size {
        case 13: 16
        case 12: 15
        case 11: 13
        default: (size * 1.2).rounded(.up)
        }
    }

    /// Centred in Chrome's line box, 11 pt text sits half a point higher than Chrome puts it.
    static func baselineShift(_ size: CGFloat) -> CGFloat {
        size == 11 ? 0.5 : 0
    }
}

/// A button that only shows its label: the surfaces draw their own hover states, and the
/// prototype's buttons have no pressed look.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}
