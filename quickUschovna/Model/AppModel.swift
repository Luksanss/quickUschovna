import AppKit
import Observation

/// Everything the surfaces show, and every action they can take. The views read it and call its
/// methods; the surface controllers show and hide windows when it changes. Ported from the
/// prototype's state machine (`design/prototype/quickUschovna v1.dc.html`, `class Component`).
@Observable
final class AppModel {
    // MARK: State the views read

    /// Packages to send, oldest first. The first is the one being worked on.
    var queue: [UploadPackage] = []
    /// Every sent link, newest first, expired ones included until they're pruned.
    var history: [LinkRecord] = []
    var bubble: Bubble?
    var isBubbleHovered = false
    var isPanelOpen = false
    /// The panel's Quit row has turned into "Quit while sending?".
    var isConfirmingQuit = false
    /// The sender's address, or "" before the first send.
    var senderEmail = ""
    /// The text in whichever email field is open: the bubble's or the panel's.
    var emailDraft = ""
    /// "That doesn’t look like an email address.", under the field that's open.
    var emailError: String?
    var isEditingEmail = false
    var launchAtLogin = false
    /// The Recent row showing "✓ Link copied" for a moment.
    var copiedRecordID: UUID?
    /// A file drag in progress anywhere on screen; the drop zone is open while it's set.
    var drag: DragSummary?
    /// A file drag is over the menu-bar icon itself.
    var isDragOverIcon = false
    /// The icon shows the check until then.
    var doneUntil: Date?
    /// The icon shows the error badge until the user sees the bubble or opens the panel.
    var hasUnseenError = false

    /// The links in Recent: valid ones, newest first.
    var recentLinks: [LinkRecord] { history.filter { $0.isValid() } }

    var iconState: MenuBarIconState {
        if isDragOverIcon || drag?.isOver == true { return .target }
        if let doneUntil, doneUntil > .now { return .done }
        if hasUnseenError { return .error }
        guard let active = queue.first else { return .idle }
        switch active.status {
        case .queued, .zipping: return .zipping
        case .connecting, .uploading: return .progress(active.fractionSent)
        case .reconnecting, .failed: return .paused(active.fractionSent)
        }
    }

    // MARK: Actions the views take

    /// Sends what was dropped (or picked in Finder) as one package.
    func send(_ urls: [URL]) {}

    /// Return in the first-run bubble's email field.
    func submitBubbleEmail() {}

    /// Try Again, in the bubble or on the failed package's row.
    func retry() {}

    func cancel(_ packageID: UUID) {}

    /// A click on a Recent row: copies its link again.
    func copyLink(of record: LinkRecord) {}

    /// The ↗ button on a Recent row.
    func openLink(of record: LinkRecord) {}

    /// A click on the bubble: opens the link of "Link copied", or marks an error as seen.
    func bubbleClicked() {}

    func setBubbleHovered(_ hovered: Bool) {}

    /// A click on the sender address in the panel.
    func startEditingEmail() {}

    /// Return in the panel's email field: saves a valid address, or shows the error.
    func commitPanelEmail() {}

    /// The panel's email field lost focus: saves a valid address, or drops the edit.
    func endEditingEmail() {}

    func toggleLaunchAtLogin() {}

    /// "Quit quickUschovna": quits, or asks first while something is sending.
    func quitClicked() {}

    func cancelQuit() {}

    func quitNow() {}
}
