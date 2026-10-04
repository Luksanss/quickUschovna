import SwiftUI

/// The panel that opens on a click on the icon, including its chrome and shadow room. Top to
/// bottom: what's sending, the links in Recent, then the sender address, Launch at Login and Quit.
struct PanelView: View {
    let model: AppModel

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.queue.isEmpty {
                SectionHeader(title: "Sending")
                ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, package in
                    UploadRow(package: package, isFirst: index == 0,
                              cancel: { model.cancel(package.id) }, retry: model.retry)
                }
                SurfaceSeparator()
            }
            SectionHeader(title: "Recent")
            RecentList(model: model)
            SurfaceSeparator()
            SenderRow(model: model)
            if model.isEditingEmail, let error = model.emailError {
                Text(error)
                    .surfaceFont(11)
                    .foregroundStyle(tokens.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 4, trailing: 10))
            }
            HoverRow(height: 30, action: model.toggleLaunchAtLogin) {
                HStack(spacing: 8) {
                    Text("Launch at Login")
                        .surfaceFont(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Centred, the switch would sit 7.5 pt down the row; Chrome paints it at 8.
                    SurfaceSwitch(isOn: model.launchAtLogin)
                        .offset(y: 0.5)
                }
                .padding(.horizontal, 10)
            }
            SurfaceSeparator()
            if model.isConfirmingQuit {
                QuitConfirmation(model: model)
            } else {
                HoverRow(height: 28, action: model.quitClicked) {
                    Text("Quit quickUschovna")
                        .surfaceFont(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                }
            }
        }
        .foregroundStyle(tokens.fg)
        .surfaceChrome(padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), entrance: .slideIn)
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        Text(title)
            .surfaceFont(11, .semibold)
            .foregroundStyle(tokens.fg2)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 2, trailing: 10))
    }
}

/// A full-width row that highlights under the pointer and runs its action on a click.
private struct HoverRow<Content: View>: View {
    let height: CGFloat
    let action: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.surfaceTokens) private var tokens
    @State private var isHovered = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(isHovered ? tokens.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .circular))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}

// MARK: - Sending

/// One package in Sending: its name and a cancel button, a bar for the first one, and what's
/// happening to it.
private struct UploadRow: View {
    let package: UploadPackage
    /// The first package is the one being worked on; the rest wait behind it.
    let isFirst: Bool
    let cancel: () -> Void
    let retry: () -> Void

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        let status = UploadStatus(package: package, isFirst: isFirst)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SplitName(name: package.label)
                    .surfaceFont(13, .medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(package.label)
                CancelButton(action: cancel)
            }
            if status.showsBar {
                ProgressBar(fraction: status.fraction, color: status.isBarDimmed ? tokens.fg3 : tokens.accent)
            }
            HStack(spacing: 8) {
                Text(status.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(status.isError ? tokens.red : tokens.fg2)
                if status.isError {
                    Button(action: retry) {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .foregroundStyle(tokens.accent)
                    }
                    .buttonStyle(BareButtonStyle())
                }
            }
            .surfaceFont(11)
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 7, trailing: 10))
    }
}

/// What a package's row says, and how its bar looks: the prototype's `uploads` mapping.
private struct UploadStatus {
    var text: String
    var fraction = 0.0
    var showsBar = true
    /// `--fg3` instead of the accent: zipping, reconnecting and failed.
    var isBarDimmed = false
    var isError = false

    init(package: UploadPackage, isFirst: Bool) {
        let sent = Format.size(package.sent), total = Format.size(package.bytes)
        guard isFirst else {
            text = "Waiting · \(total)"
            showsBar = false
            return
        }
        switch package.status {
        case .queued where package.zipTotal == 0:
            // About to connect. The prototype moves on within a tick, so it never shows this.
            text = "Connecting to Úschovna…"
        case .queued, .zipping:
            text = "Zipping “\(package.zipName)”…"
            fraction = package.fractionZipped
            isBarDimmed = true
        case .connecting:
            text = package.sent > 0 ? "Resuming at \(sent)…" : "Connecting to Úschovna…"
            fraction = package.fractionSent
        case .uploading:
            text = "\(sent) of \(total)"
            if let speed = package.bytesPerSecond, speed > 0 {
                text += " · " + Format.timeLeft(seconds: Double(package.bytes - package.sent) / speed)
            }
            fraction = package.fractionSent
        case .reconnecting:
            text = "Reconnecting… \(sent) of \(total) sent"
            fraction = package.fractionSent
            isBarDimmed = true
        case .failed:
            text = "Úschovna isn’t answering"
            fraction = package.fractionSent
            isBarDimmed = true
            isError = true
        }
    }
}

/// A 4 pt bar on a `--fill` track.
private struct ProgressBar: View {
    let fraction: Double
    let color: Color

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .circular)
            .fill(tokens.fill)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2, style: .circular)
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .circular))
            .frame(height: 4)
    }
}

/// The 18 pt round × on a package's row.
private struct CancelButton: View {
    let action: () -> Void

    @Environment(\.surfaceTokens) private var tokens
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isHovered ? tokens.fg3 : tokens.fill)
                .frame(width: 18, height: 18)
                .overlay {
                    SurfaceIcon(.cross)
                        .fill(isHovered ? tokens.fg : tokens.fg2)
                        .frame(width: 8, height: 8)
                }
        }
        .buttonStyle(BareButtonStyle())
        .onHover { isHovered = $0 }
        .help("Cancel")
    }
}

// MARK: - Recent

/// The links Úschovna still keeps, newest first, up to 236 pt tall before it scrolls.
private struct RecentList: View {
    let model: AppModel

    @Environment(\.surfaceTokens) private var tokens

    private static let maxHeight: CGFloat = 236

    var body: some View {
        let links = model.recentLinks
        if links.isEmpty {
            Text("Links you send stay here for \(Limits.retentionDays) days.")
                .surfaceFont(12)
                .foregroundStyle(tokens.fg2)
                .padding(EdgeInsets(top: 3, leading: 10, bottom: 8, trailing: 10))
        } else if CGFloat(links.count) * RecentRow.height > Self.maxHeight {
            ScrollView {
                rows(links)
            }
            .frame(height: Self.maxHeight)
        } else {
            rows(links)
        }
    }

    private func rows(_ links: [LinkRecord]) -> some View {
        VStack(spacing: 0) {
            ForEach(links) { record in
                RecentRow(record: record, isCopied: model.copiedRecordID == record.id,
                          copy: { model.copyLink(of: record) }, open: { model.openLink(of: record) })
            }
        }
    }
}

/// A sent link: a click copies it again, ↗ opens it.
private struct RecentRow: View {
    static let height: CGFloat = 40

    let record: LinkRecord
    let isCopied: Bool
    let copy: () -> Void
    let open: () -> Void

    @Environment(\.surfaceTokens) private var tokens
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                SplitName(name: record.label)
                    .surfaceFont(13)
                    .help(record.label)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            OpenButton(action: open)
        }
        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 6))
        .frame(height: Self.height)
        .background(isHovered ? tokens.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .circular))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: copy)
        .help("Copy the link again")
    }

    @ViewBuilder private var meta: some View {
        if isCopied {
            Text("✓ Link copied")
                .surfaceFont(11)
                .foregroundStyle(tokens.accent)
        } else {
            let left = Format.daysLeft(until: record.expires)
            Text("\(Format.size(record.bytes)) · \(left.text)")
                .surfaceFont(11)
                .foregroundStyle(left.isSoon ? tokens.orange : tokens.fg2)
        }
    }
}

/// ↗ on a Recent row. Being a button, it takes the click, so the row doesn't copy too.
private struct OpenButton: View {
    let action: () -> Void

    @Environment(\.surfaceTokens) private var tokens
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SurfaceIcon(.openArrow)
                .fill(isHovered ? tokens.fg : tokens.fg3)
                .frame(width: 11, height: 11)
                // Centred, the arrow would sit 6.5 pt in; Chrome paints it at 7.
                .offset(x: 0.5, y: 0.5)
                .frame(width: 24, height: 24)
                .background(isHovered ? tokens.fill : .clear, in: RoundedRectangle(cornerRadius: 6, style: .circular))
        }
        .buttonStyle(BareButtonStyle())
        .onHover { isHovered = $0 }
        .help("Open in browser")
    }
}

// MARK: - Settings

/// "Sender" and the address, which turns into a field on a click.
private struct SenderRow: View {
    let model: AppModel

    @Environment(\.surfaceTokens) private var tokens
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Sender")
                .surfaceFont(13)
            Spacer(minLength: 0)
            if model.isEditingEmail {
                EmailField(text: Binding(get: { model.emailDraft }, set: { model.emailDraft = $0 }),
                           height: 22, cornerRadius: 5, horizontalPadding: 6, alignment: .trailing,
                           onSubmit: model.commitPanelEmail, onFocusLost: model.endEditingEmail)
                    .frame(width: 186)
            } else {
                Button(action: model.startEditingEmail) {
                    Text(model.senderEmail.isEmpty ? "Not set" : model.senderEmail)
                        .surfaceFont(13)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isHovered ? tokens.fg : tokens.fg2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(isHovered ? tokens.hover : .clear, in: RoundedRectangle(cornerRadius: 5, style: .circular))
                        .frame(maxWidth: 190, alignment: .trailing)
                }
                .buttonStyle(BareButtonStyle())
                .onHover { isHovered = $0 }
                .help("Change the sender email")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
    }
}

/// Quitting while something is sending asks first, in place of the Quit row.
private struct QuitConfirmation: View {
    let model: AppModel

    @Environment(\.surfaceTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quit while sending?")
                    .surfaceFont(13, .semibold)
                Text(detail)
                    .surfaceFont(12)
                    .foregroundStyle(tokens.fg2)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                SurfaceButton(title: "Cancel", isProminent: false, action: model.cancelQuit)
                SurfaceButton(title: "Quit", action: model.quitNow)
            }
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
    }

    /// "report.mov hasn’t finished uploading." or "2 uploads haven’t finished."
    private var detail: String {
        if model.queue.count == 1, let package = model.queue.first {
            return "\(package.label) hasn’t finished uploading."
        }
        return "\(model.queue.count) uploads haven’t finished."
    }
}
