import AppKit
import Observation
import os

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
    /// The text in whichever email field is open: the bubble's or the panel's. Typing clears the
    /// error, as in the prototype.
    var emailDraft = "" {
        didSet { if emailDraft != oldValue { emailError = nil } }
    }
    /// "That doesn’t look like an email address.", under the field that's open.
    var emailError: String?
    var isEditingEmail = false
    var launchAtLogin = false
    /// The Recent row showing "✓ Link copied" for a moment.
    var copiedRecordID: UUID?
    /// A file drag in progress anywhere on screen (`DragMonitor`).
    var drag: DragSummary?
    /// A file drag is over the menu-bar icon itself.
    var isDragOverIcon = false
    /// The icon shows the check until then.
    var doneUntil: Date?
    /// The icon shows the error badge until the user sees the bubble or opens the panel.
    var hasUnseenError = false

    /// The links in Recent: valid ones, newest first.
    var recentLinks: [LinkRecord] { history.filter { $0.isValid() } }

    /// The drop zone opens once a file drag comes near the menu-bar icon (`DragMonitor`) or onto it,
    /// and stays until the drag ends. The prototype opens it for every file drag, which on a real
    /// desktop got in the way of ordinary drags in Finder. Waiting for the icon itself made the drag
    /// run into the top of the screen, which macOS takes as a request for Mission Control.
    var isDropZoneOpen: Bool { drag?.isZoneOpen == true }

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

    // MARK: Timings, from the prototype

    /// "Link copied" stays this long, unless hovered.
    private static let copiedBubbleDuration: TimeInterval = 3
    /// After the pointer leaves a timed bubble, it stays this much longer.
    private static let bubbleLingerAfterHover: TimeInterval = 1.5
    private static let tooBigBubbleDuration: TimeInterval = 5
    /// The icon's check after a link is copied.
    private static let doneDuration: TimeInterval = 2.5
    /// "✓ Link copied" in a Recent row after an upload finishes while the panel is open.
    private static let copiedRowAfterUpload: TimeInterval = 1.8
    /// "✓ Link copied" after a click on a Recent row.
    private static let copiedRowAfterClick: TimeInterval = 1.4

    static let invalidEmailMessage = "That doesn’t look like an email address."

    // MARK: Private state

    @ObservationIgnored private let service: UploadService
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "model")
    /// Items waiting for the first-run email bubble.
    @ObservationIgnored private var pendingItems: [URL]?
    /// When a timed bubble goes away, unless it's hovered.
    @ObservationIgnored private var bubbleUntil: Date?
    @ObservationIgnored private var bubbleTimer: Task<Void, Never>?
    @ObservationIgnored private var doneTimer: Task<Void, Never>?
    @ObservationIgnored private var copiedTimer: Task<Void, Never>?
    /// The task working on the first package, if any.
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var workerPackageID: UUID?
    /// Kept per package so Try Again resumes the same Úschovna package instead of starting over.
    @ObservationIgnored private var sessions: [UUID: UploadSession] = [:]
    @ObservationIgnored private var preparedFiles: [UUID: [UploadFile]] = [:]
    @ObservationIgnored private var speed: [UUID: SpeedMeter] = [:]
    /// Keeps the Mac awake while something is sending.
    @ObservationIgnored private var activity: NSObjectProtocol?

    init(service: UploadService = UschovnaService(), store: SettingsStore = .standard) {
        self.service = service
        self.store = store
        senderEmail = store.senderEmail ?? ""
        history = store.loadHistory().filter { $0.isValid() }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: Sending

    /// Sends what was dropped (or picked in Finder) as one package.
    func send(_ urls: [URL]) {
        let items = urls.filter(\.isFileURL)
        guard !items.isEmpty else { return }
        // As the prototype's `send`: a drop closes everything else that's open.
        drag = nil
        isDragOverIcon = false
        isPanelOpen = false
        isConfirmingQuit = false
        isEditingEmail = false
        isBubbleHovered = false
        Task {
            let bytes = await FileMeasure.totalSize(of: items)
            self.enqueue(items, bytes: bytes)
        }
    }

    private func enqueue(_ items: [URL], bytes: Int64) {
        let label = Format.packageLabel(for: items)
        if bytes > Limits.freePackageBytes {
            logger.info("Refused \(items.count, privacy: .public) items: \(bytes, privacy: .public) bytes is over the limit")
            showBubble(.tooBig(bytes: bytes), for: Self.tooBigBubbleDuration)
            return
        }
        guard !senderEmail.isEmpty else {
            pendingItems = items
            emailDraft = ""
            emailError = nil
            showBubble(.email(label: label), for: nil)
            return
        }
        // A copied or failed bubble that's already out stays; anything else gives way.
        if let bubble {
            switch bubble {
            case .copied, .failed: break
            case .email, .tooBig: hideBubble()
            }
        }
        let folders = items.filter(FileMeasure.isDirectory)
        var package = UploadPackage(id: UUID(), label: label, items: items, bytes: bytes)
        package.zipName = folders.count == 1 ? folders[0].lastPathComponent : "\(folders.count) folders"
        queue.append(package)
        logger.info("Queued a package of \(items.count, privacy: .public) items, \(bytes, privacy: .public) bytes")
        updateActivity()
        startNext()
    }

    /// Starts work on the first package, unless something is already on it or it failed.
    private func startNext() {
        guard worker == nil, let first = queue.first, first.status != .failed else { return }
        let id = first.id
        workerPackageID = id
        worker = Task {
            await self.work(on: id)
            if self.workerPackageID == id {
                self.worker = nil
                self.workerPackageID = nil
            }
            self.startNext()
        }
    }

    private func work(on id: UUID) async {
        do {
            let files = try await prepare(id)
            guard !Task.isCancelled, index(of: id) != nil else { return }
            let session = sessions[id] ?? service.makeSession(files: files, sender: senderEmail)
            sessions[id] = session
            update(id) { $0.status = .connecting }
            let link = try await session.run { [weak self] event in
                self?.handle(event, for: id)
            }
            guard index(of: id) != nil else { return }
            finish(id, link: link)
        } catch is CancellationError {
            logger.info("Package cancelled")
        } catch {
            guard !Task.isCancelled, index(of: id) != nil else { return }
            fail(id, error)
        }
    }

    /// Zips the package's folders, once. Plain files go as they are.
    private func prepare(_ id: UUID) async throws -> [UploadFile] {
        if let files = preparedFiles[id] { return files }
        guard let package = queue.first(where: { $0.id == id }) else { throw CancellationError() }
        let folders = package.items.filter(FileMeasure.isDirectory)
        if !folders.isEmpty {
            let folderBytes = await FileMeasure.totalSize(of: folders)
            update(id) {
                $0.status = .zipping
                $0.zipTotal = folderBytes
                $0.zipDone = 0
            }
        }
        var files: [UploadFile] = []
        var zippedSoFar: Int64 = 0
        for item in package.items {
            try Task.checkCancellation()
            if FileMeasure.isDirectory(item) {
                let base = zippedSoFar
                let zip = try await Zipper.zip(folder: item, packageID: id) { [weak self] done in
                    self?.update(id) { $0.zipDone = min($0.zipTotal, base + done) }
                }
                zippedSoFar += await FileMeasure.totalSize(of: [item])
                files.append(UploadFile(url: zip.url, name: item.lastPathComponent + ".zip", size: zip.size))
            } else {
                let size = await FileMeasure.totalSize(of: [item])
                files.append(UploadFile(url: item, name: item.lastPathComponent, size: size))
            }
        }
        preparedFiles[id] = files
        let total = files.reduce(0) { $0 + $1.size }
        update(id) { $0.bytes = total }
        return files
    }

    private func handle(_ event: UploadEvent, for id: UUID) {
        let now = Date.now
        update(id) { package in
            switch event {
            case .connecting(let sent):
                package.status = .connecting
                package.sent = sent
                speed[id] = nil
                package.bytesPerSecond = nil
            case .progress(let sent):
                package.status = .uploading
                package.sent = sent
                var meter = speed[id] ?? SpeedMeter()
                meter.add(sent: sent, at: now)
                speed[id] = meter
                package.bytesPerSecond = meter.bytesPerSecond
            case .waitingForNetwork(let sent):
                package.status = .reconnecting
                package.sent = sent
                speed[id] = nil
                package.bytesPerSecond = nil
            }
        }
    }

    private func finish(_ id: UUID, link: URL) {
        guard let index = index(of: id) else { return }
        let package = queue.remove(at: index)
        cleanUp(id)
        let record = LinkRecord(id: UUID(), label: package.label, bytes: package.bytes, link: link,
                                sentAt: .now, expires: Calendar.current.date(byAdding: .day, value: Limits.retentionDays, to: .now) ?? .now)
        history.insert(record, at: 0)
        store.saveHistory(history)
        copyToClipboard(link)
        logger.info("Sent a package of \(package.bytes, privacy: .public) bytes")
        showDone()
        if isPanelOpen {
            flashCopied(record.id, for: Self.copiedRowAfterUpload)
        } else {
            isBubbleHovered = false
            showBubble(.copied(label: record.label, bytes: record.bytes, expires: record.expires, link: link),
                       for: Self.copiedBubbleDuration)
        }
        if queue.isEmpty { isConfirmingQuit = false }
        updateActivity()
    }

    private func fail(_ id: UUID, _ error: Error) {
        logger.error("Package failed: \(String(describing: error), privacy: .public)")
        update(id) { $0.status = .failed }
        guard let package = queue.first(where: { $0.id == id }) else { return }
        if !isPanelOpen {
            isBubbleHovered = false
            showBubble(.failed(label: package.label, packageID: id), for: nil)
            hasUnseenError = true
        }
    }

    /// Try Again, in the bubble or on the failed package's row.
    func retry() {
        guard let first = queue.first, first.status == .failed else { return }
        update(first.id) { $0.status = .connecting }
        hideBubble()
        hasUnseenError = false
        startNext()
    }

    func cancel(_ packageID: UUID) {
        guard index(of: packageID) != nil else { return }
        queue.removeAll { $0.id == packageID }
        if workerPackageID == packageID {
            worker?.cancel()
            worker = nil
            workerPackageID = nil
        }
        cleanUp(packageID)
        if case .failed(_, let failedID) = bubble, failedID == packageID { hideBubble() }
        if queue.first?.status != .failed { hasUnseenError = false }
        if queue.isEmpty { isConfirmingQuit = false }
        updateActivity()
        startNext()
    }

    private func cleanUp(_ id: UUID) {
        sessions[id] = nil
        preparedFiles[id] = nil
        speed[id] = nil
        Zipper.removeArchives(for: id)
    }

    // MARK: Links

    /// A click on a Recent row: copies its link again.
    func copyLink(of record: LinkRecord) {
        copyToClipboard(record.link)
        flashCopied(record.id, for: Self.copiedRowAfterClick)
    }

    /// The ↗ button on a Recent row.
    func openLink(of record: LinkRecord) {
        NSWorkspace.shared.open(record.link)
    }

    private func copyToClipboard(_ link: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link.absoluteString, forType: .string)
    }

    private func flashCopied(_ recordID: UUID, for duration: TimeInterval) {
        copiedRecordID = recordID
        copiedTimer?.cancel()
        copiedTimer = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.copiedRecordID = nil
        }
    }

    private func showDone() {
        doneUntil = .now.addingTimeInterval(Self.doneDuration)
        doneTimer?.cancel()
        doneTimer = Task {
            try? await Task.sleep(for: .seconds(Self.doneDuration))
            guard !Task.isCancelled else { return }
            self.doneUntil = nil
        }
    }

    // MARK: The bubble

    private func showBubble(_ newBubble: Bubble, for duration: TimeInterval?) {
        bubble = newBubble
        bubbleUntil = duration.map { .now.addingTimeInterval($0) }
        scheduleBubbleTimeout()
    }

    private func hideBubble() {
        bubble = nil
        bubbleUntil = nil
        pendingItems = nil
        bubbleTimer?.cancel()
    }

    private func scheduleBubbleTimeout() {
        bubbleTimer?.cancel()
        guard let until = bubbleUntil else { return }
        bubbleTimer = Task {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled, !self.isBubbleHovered, let until = self.bubbleUntil, until <= .now else { return }
            self.bubble = nil
            self.bubbleUntil = nil
        }
    }

    /// A click on the bubble: opens the link of "Link copied", or marks an error as seen.
    func bubbleClicked() {
        switch bubble {
        case .copied(_, _, _, let link):
            NSWorkspace.shared.open(link)
            hideBubble()
        case .failed:
            hasUnseenError = false
        default:
            break
        }
    }

    func setBubbleHovered(_ hovered: Bool) {
        isBubbleHovered = hovered
        if hovered {
            bubbleTimer?.cancel()
        } else if bubbleUntil != nil {
            bubbleUntil = .now.addingTimeInterval(Self.bubbleLingerAfterHover)
            scheduleBubbleTimeout()
        }
    }

    /// Return in the first-run bubble's email field.
    func submitBubbleEmail() {
        let address = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(address) else {
            emailError = Self.invalidEmailMessage
            return
        }
        let items = pendingItems
        setSenderEmail(address)
        emailError = nil
        hideBubble()
        if let items { send(items) }
    }

    // MARK: The panel

    /// A click on the menu-bar icon.
    func togglePanel() {
        if isPanelOpen {
            closePanel()
        } else {
            isPanelOpen = true
            hideBubble()
            hasUnseenError = false
            history = history.filter { $0.isValid() }
        }
    }

    func closePanel() {
        isPanelOpen = false
        isConfirmingQuit = false
        isEditingEmail = false
        emailError = nil
    }

    /// A click on the sender address in the panel.
    func startEditingEmail() {
        emailDraft = senderEmail
        emailError = nil
        isEditingEmail = true
    }

    /// Return in the panel's email field: saves a valid address, or shows the error.
    func commitPanelEmail() {
        let address = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isValidEmail(address) {
            setSenderEmail(address)
            isEditingEmail = false
            emailError = nil
        } else {
            emailError = Self.invalidEmailMessage
        }
    }

    /// The panel's email field lost focus: saves a valid address, or drops the edit.
    func endEditingEmail() {
        guard isEditingEmail else { return }
        let address = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isValidEmail(address) { setSenderEmail(address) }
        isEditingEmail = false
        emailError = nil
    }

    func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// "Quit quickUschovna": quits, or asks first while something is sending.
    func quitClicked() {
        if queue.isEmpty {
            quitNow()
        } else {
            isConfirmingQuit = true
        }
    }

    func cancelQuit() {
        isConfirmingQuit = false
    }

    func quitNow() {
        for package in queue { cancel(package.id) }
        NSApp.terminate(nil)
    }

    // MARK: The drag

    /// A file drag came over the menu-bar icon (true) or left it (false). Reaching the icon opens
    /// the drop zone for the rest of the drag, if coming near it hasn't already.
    func dragOverIcon(_ over: Bool) {
        isDragOverIcon = over
        if over { drag?.isZoneOpen = true }
    }

    // MARK: Dismissal, from the surfaces

    /// Esc, in whichever surface has the keyboard. The prototype's `escape`.
    func escape() {
        if isEditingEmail {
            isEditingEmail = false
            emailError = nil
        } else if isPanelOpen {
            closePanel()
        } else if bubble != nil {
            if case .failed = bubble { hasUnseenError = false }
            hideBubble()
        }
    }

    /// A click anywhere outside the surfaces. Closes the panel and any bubble that isn't
    /// "Link copied", which goes away by itself.
    func clickedOutside() {
        if isPanelOpen { closePanel() }
        guard let bubble else { return }
        switch bubble {
        case .copied:
            break
        case .failed:
            hasUnseenError = false
            hideBubble()
        case .email, .tooBig:
            hideBubble()
        }
    }

    // MARK: Helpers

    private func setSenderEmail(_ address: String) {
        senderEmail = address
        store.senderEmail = address
    }

    /// The prototype's check: something, an @, something, a dot, something.
    static func isValidEmail(_ address: String) -> Bool {
        address.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }

    private func index(of id: UUID) -> Int? {
        queue.firstIndex { $0.id == id }
    }

    private func update(_ id: UUID, _ change: (inout UploadPackage) -> Void) {
        guard let index = index(of: id) else { return }
        change(&queue[index])
    }

    private func updateActivity() {
        if queue.isEmpty {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        } else if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                             reason: "Sending a package to Úschovna")
        }
    }
}

/// A smoothed upload speed over the last few seconds, for "3 min left".
struct SpeedMeter {
    private var samples: [(date: Date, sent: Int64)] = []
    private static let window: TimeInterval = 5
    /// Too little to go on before this, so no time left is shown yet.
    private static let minimumSpan: TimeInterval = 1

    mutating func add(sent: Int64, at date: Date) {
        samples.append((date, sent))
        samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
    }

    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= Self.minimumSpan, last.sent > first.sent else { return nil }
        return Double(last.sent - first.sent) / span
    }
}
