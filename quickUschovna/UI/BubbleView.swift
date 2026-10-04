import SwiftUI

/// The bubble under the icon (`model.bubble`), including its chrome and shadow room: a 28 pt badge
/// and up to three lines, in one of four versions. A click anywhere on it goes to
/// `model.bubbleClicked()`, except on Try Again and in the email field.
struct BubbleView: View {
    let model: AppModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceBody(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .onHover { model.setBubbleHovered($0) }
            .onTapGesture { model.bubbleClicked() }
            .surfaceWindow(entrance: .slideIn)
    }

    @ViewBuilder private var content: some View {
        switch model.bubble {
        case .copied(let label, let bytes, let expires, _):
            CopiedBubble(label: label, bytes: bytes, expires: expires, isHovered: model.isBubbleHovered)
        case .email(let label):
            EmailBubble(model: model, label: label)
        case .tooBig(let bytes):
            TooBigBubble(bytes: bytes)
        case .failed(let label, _):
            FailedBubble(label: label, retry: model.retry)
        case nil:
            EmptyView()
        }
    }
}

/// A badge, then the bubble's lines beside it, top-aligned.
private struct BubbleLayout<Badge: View, Lines: View>: View {
    var linesSpacing: CGFloat = 2
    @ViewBuilder let badge: Badge
    @ViewBuilder let lines: Lines

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            badge
            VStack(alignment: .leading, spacing: linesSpacing) {
                lines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Link copied": what was sent and until when the link works. ↗ shows while hovered, since a
/// click opens the link.
private struct CopiedBubble: View {
    let label: String
    let bytes: Int64
    let expires: Date
    let isHovered: Bool

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            BubbleLayout {
                BubbleBadge(color: tokens.accent) {
                    SurfaceIcon(.check).fill(.white).frame(width: 14, height: 14)
                }
            } lines: {
                Text("Link copied")
                    .surfaceFont(13, .semibold)
                SplitName(name: label, suffix: " · \(Format.size(bytes))")
                    .surfaceFont(12)
                    .foregroundStyle(tokens.fg2)
                Text("Expires \(Format.day(expires))")
                    .surfaceFont(12)
                    .foregroundStyle(tokens.fg2)
            }
            if isHovered {
                SurfaceIcon(.openArrow)
                    .fill(tokens.fg2)
                    .frame(width: 12, height: 12)
                    .padding(.top, 2)
                    .help("Open in browser")
            }
        }
        .foregroundStyle(tokens.fg)
    }
}

/// The first drop ever: the sender's address, in a field that has focus. Return sends.
private struct EmailBubble: View {
    let model: AppModel
    let label: String

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        BubbleLayout(linesSpacing: 7) {
            BubbleBadge(color: tokens.fill) {
                // The prototype's glyph sits a point above the badge's middle: its 19 pt line box
                // is centred with the glyph at the top of it, 1.5 pt up, which Chrome paints
                // snapped to 1.
                MenuBarGlyph(state: .idle, size: 16)
                    .foregroundStyle(tokens.fg)
                    .offset(y: -1)
            }
        } lines: {
            Text("Your email (the sender)")
                .surfaceFont(13, .semibold)
                .foregroundStyle(tokens.fg)
            EmailField(text: Binding(get: { model.emailDraft }, set: { model.emailDraft = $0 }),
                       placeholder: "name@example.com",
                       height: 26, cornerRadius: 7, horizontalPadding: 8,
                       onSubmit: model.submitBubbleEmail)
            Group {
                if let error = model.emailError {
                    Text(error).foregroundStyle(tokens.red)
                } else {
                    Text("Press Return to send \(label).").foregroundStyle(tokens.fg2)
                }
            }
            .surfaceFont(11, lineHeight: 15)
        }
    }
}

/// Over 30 GB: nothing was uploaded.
private struct TooBigBubble: View {
    let bytes: Int64

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        BubbleLayout {
            BubbleBadge(color: SurfaceTokens.warningBadge) {
                SurfaceIcon(.exclamation).fill(.white).frame(width: 14, height: 14)
            }
        } lines: {
            Text("\(Format.size(bytes)) is too big")
                .surfaceFont(13, .semibold)
                .foregroundStyle(tokens.fg)
            Text("Free packages are limited to \(Format.size(Limits.freePackageBytes)).")
                .surfaceFont(12)
                .foregroundStyle(tokens.fg2)
        }
    }
}

/// Úschovna failed: the package waits for Try Again.
private struct FailedBubble: View {
    let label: String
    let retry: () -> Void

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        BubbleLayout {
            BubbleBadge(color: SurfaceTokens.errorBadge) {
                SurfaceIcon(.exclamation).fill(.white).frame(width: 14, height: 14)
            }
        } lines: {
            Text("Úschovna isn’t answering")
                .surfaceFont(13, .semibold)
                .foregroundStyle(tokens.fg)
            SplitName(name: label, suffix: " is waiting to be sent.")
                .surfaceFont(12)
                .foregroundStyle(tokens.fg2)
            SurfaceButton(title: "Try Again", action: retry)
                .padding(.top, 8)
        }
    }
}
