#if DEBUG
import AppKit
import os

/// Drives a Debug build from outside, for trying the surfaces without a mouse: post the distributed
/// notification `com.luksanss.quickUschovna.debug` with the command as its object and the
/// arguments under `args` in its user info. `scripts/debug-control.swift` posts them.
///
/// Commands: `send <path>…` (as a drop), `drag <path>…` (a file drag starts), `over` / `out` (the
/// drag moves over the drop zone / off it), `icon` (over the menu-bar icon), `enddrag`, `panel`
/// (a click on the icon), `outside` (a click in another app), `escape`, `email <address>` (typed
/// into whichever email field is open, then Return), `copy <index>` (a click on a Recent row),
/// `cancel` (the first package's cancel button), `retry`, `hover` / `unhover` (the bubble),
/// `editemail`, `quit`, `dump <file>` (the model's state and every window's frame, as text).
final class DebugControl {
    static let notificationName = Notification.Name("com.luksanss.quickUschovna.debug")
    private let model: AppModel
    private let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "debug")
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            let command = note.object as? String ?? ""
            let args = note.userInfo?["args"] as? [String] ?? []
            MainActor.assumeIsolated { self?.run(command, args) }
        }
    }

    private func run(_ command: String, _ args: [String]) {
        logger.info("Debug command: \(command, privacy: .public)")
        let urls = args.map { URL(fileURLWithPath: $0) }
        switch command {
        case "send": model.send(urls)
        case "drag": model.drag = DragSummary(label: Format.packageLabel(for: urls), bytes: nil)
            Task {
                let bytes = await FileMeasure.totalSize(of: urls)
                self.model.drag?.bytes = bytes
            }
        case "over": model.drag?.isOver = true
        case "out": model.drag?.isOver = false
        case "icon": model.isDragOverIcon = true
        case "enddrag":
            model.drag = nil
            model.isDragOverIcon = false
        case "panel": model.togglePanel()
        case "outside": model.clickedOutside()
        case "escape": model.escape()
        case "email":
            model.emailDraft = args.first ?? ""
            if model.isEditingEmail { model.commitPanelEmail() } else { model.submitBubbleEmail() }
        case "editemail": model.startEditingEmail()
        case "copy":
            let links = model.recentLinks
            if let index = args.first.flatMap(Int.init), links.indices.contains(index) { model.copyLink(of: links[index]) }
        case "cancel": if let first = model.queue.first { model.cancel(first.id) }
        case "retry": model.retry()
        case "hover": model.setBubbleHovered(true)
        case "unhover": model.setBubbleHovered(false)
        case "quit": model.quitClicked()
        case "dump": dump(to: args.first ?? "/dev/stdout")
        default: logger.error("Unknown debug command: \(command, privacy: .public)")
        }
    }

    private func dump(to path: String) {
        var lines = [
            "icon: \(model.iconState)",
            "panel: \(model.isPanelOpen) confirmingQuit: \(model.isConfirmingQuit) editingEmail: \(model.isEditingEmail)",
            "bubble: \(model.bubble.map { String(describing: $0) } ?? "none") hovered: \(model.isBubbleHovered)",
            "drag: \(model.drag.map { String(describing: $0) } ?? "none") overIcon: \(model.isDragOverIcon)",
            "sender set: \(!model.senderEmail.isEmpty) emailError: \(model.emailError ?? "none")",
            "unseenError: \(model.hasUnseenError) copiedRow: \(model.copiedRecordID != nil)",
        ]
        for package in model.queue {
            lines.append("package: \(package.label) \(package.status) \(package.sent)/\(package.bytes) zip \(package.zipDone)/\(package.zipTotal) speed \(package.bytesPerSecond.map { String(Int($0)) } ?? "-")")
        }
        for record in model.recentLinks {
            lines.append("recent: \(record.label) \(record.bytes) \(record.link.absoluteString)")
        }
        for window in NSApp.windows {
            lines.append("window: \(type(of: window)) visible: \(window.isVisible) key: \(window.isKeyWindow) level: \(window.level.rawValue) frame: \(NSStringFromRect(window.frame))")
        }
        let screens = NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: ", ")
        lines.append("screens: \(screens)")
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
