import Foundation
import os

/// One package's upload to Úschovna. It keeps where it got to (the package's code, which file,
/// which byte), so a `run` after a failure continues there instead of sending everything again.
///
/// It lives on the main actor like the rest of the app, but only to keep its bookkeeping in one
/// place: every request is an `await` on URLSession, and files are read by `FileChunks` off the
/// main actor, so the menu bar never waits on the network or the disk.
final class UschovnaSession: UploadSession {
    /// A file as it's sent: never empty, with its name composed the way Úschovna should show it.
    private struct Item {
        let url: URL
        let name: String
        let size: Int64
    }

    /// A package Úschovna has, and how far into it the upload got.
    private struct Package {
        /// Where the chunks go: the upload host `package_target` named, or the site.
        let host: WebOrigin
        let code: String
        var fileIndex = 0
        /// The next byte of the current file, as Úschovna last confirmed it (`usize`).
        var offset: Int64 = 0
        /// Úschovna's handle on the current file's partial upload, quoted back with each chunk.
        var tmp = ""
        /// When the page would last have sent `still_alive`, or created the package.
        var lastKeepAlive = ContinuousClock.now
    }

    private let client: UschovnaClient
    private let items: [Item]
    private let totalBytes: Int64
    private let sender: String
    private let timing: UschovnaTiming
    private let makeNetworkWatch: @Sendable () -> any NetworkWatching

    private var package: Package?
    private var link: URL?
    private var isRunning = false
    /// The last chunk's speed, which sizes the next one, as the page's `rychlost`.
    private var speed: Int64 = 0
    /// Answers in a row that didn't move the offset forward.
    private var repliesWithoutProgress = 0
    private var lastProgressReport: ContinuousClock.Instant?
    private var onEvent: (@MainActor (UploadEvent) -> Void)?
    private var watch: (any NetworkWatching)?

    init(site: URL, files: [UploadFile], sender: String, timing: UschovnaTiming,
         makeNetworkWatch: @escaping @Sendable () -> any NetworkWatching) {
        client = UschovnaClient(site: site, requestTimeout: timing.requestTimeout)
        // The page can't add an empty file and skips one if it gets one, so it's never sent.
        items = files.filter { $0.size > 0 }.map {
            Item(url: $0.url, name: UschovnaWire.displayName($0.name), size: $0.size)
        }
        totalBytes = items.reduce(0) { $0 + $1.size }
        self.sender = sender
        self.timing = timing
        self.makeNetworkWatch = makeNetworkWatch
        if items.count < files.count {
            uschovnaLog.notice("Skipping \(files.count - self.items.count, privacy: .public) empty file(s), as the website does")
        }
    }

    func run(onEvent: @escaping @MainActor (UploadEvent) -> Void) async throws -> URL {
        if let link { return link }
        guard !isRunning else { throw UploadFailure.notAnswering(detail: "This upload is already running") }
        isRunning = true
        self.onEvent = onEvent
        let watch = makeNetworkWatch()
        self.watch = watch
        defer {
            watch.stop()
            self.watch = nil
            self.onEvent = nil
            isRunning = false
        }
        do {
            let link = try await send()
            self.link = link
            return link
        } catch {
            if case .cancelled = error {
                uschovnaLog.info("Upload cancelled at \(self.acknowledged, privacy: .public) of \(self.totalBytes, privacy: .public) bytes")
                throw CancellationError()
            }
            uschovnaLog.error("Upload stopped at \(self.acknowledged, privacy: .public) of \(self.totalBytes, privacy: .public) bytes: \(error.detail, privacy: .public)")
            throw UploadFailure.notAnswering(detail: error.detail)
        }
    }

    // MARK: The upload

    private func send() async throws(UploadTrouble) -> URL {
        try await checkFiles()
        emit(.connecting(sent: acknowledged))
        // A package from an earlier run that Úschovna hasn't confirmed in this one yet. If it
        // refuses to continue it, it's started over once, from nothing.
        var isResuming = package != nil
        if let package, package.fileIndex == items.count {
            uschovnaLog.info("Resuming the package on \(package.host, privacy: .public): every file is sent, so it's only finished")
        } else if let package {
            uschovnaLog.info("Resuming the package on \(package.host, privacy: .public) at file \(package.fileIndex + 1, privacy: .public) of \(self.items.count, privacy: .public), byte \(package.offset, privacy: .public)")
        } else {
            package = try await openPackage()
        }

        while let current = package, current.fileIndex < items.count {
            let item = items[current.fileIndex]
            await keepAliveIfDue()
            let (reply, sent, elapsed) = try await attempt("ajax_upload") { () async throws(UploadTrouble) in
                let length = Int(min(Int64(UschovnaWire.chunkSize(afterSpeed: speed)), item.size - current.offset))
                let body = try await readChunk(of: item, offset: current.offset, length: length)
                do throws(UploadTrouble) {
                    let (reply, elapsed) = try await client.uploadChunk(
                        on: current.host, package: current.code, name: item.name, fileSize: item.size,
                        offset: current.offset, tmp: current.tmp, body: body)
                    return (reply, body.count, elapsed)
                } catch {
                    // The page sends a failed chunk again as it was, with no timeout. This client
                    // has one, and a chunk sized for the link before a drop can be far too big for
                    // the link after it (a phone hotspot instead of Wi-Fi), so the speed is measured
                    // again from the page's smallest chunk, at the same offset.
                    if case .network = error { speed = 0 }
                    throw error
                }
            }
            switch reply {
            case .next(let offset, let tmp):
                guard offset >= 0, offset < item.size else {
                    throw .server("ajax_upload answered usize \(offset) for a file of \(item.size) bytes", retry: false)
                }
                repliesWithoutProgress = offset > current.offset ? 0 : repliesWithoutProgress + 1
                guard repliesWithoutProgress < 5 else {
                    throw .server("ajax_upload stopped taking the file at byte \(offset)", retry: false)
                }
                package?.offset = offset
                package?.tmp = tmp ?? current.tmp
            case .fileDone:
                package?.fileIndex += 1
                package?.offset = 0
                package?.tmp = ""
                repliesWithoutProgress = 0
            case .refused(let detail):
                package = nil
                guard isResuming else { throw .refused(detail) }
                uschovnaLog.notice("Úschovna won't continue the earlier package (\(detail, privacy: .public)); starting a new one")
                isResuming = false
                speed = 0
                emit(.connecting(sent: 0))
                package = try await openPackage()
                continue
            }
            isResuming = false
            speed = UschovnaWire.speed(bytes: sent, elapsed: elapsed)
            reportProgress(force: package?.offset == 0)
        }

        return try await finish()
    }

    /// Loads the page, asks where to upload, and creates the package, as the page's Send button
    /// does.
    private func openPackage() async throws(UploadTrouble) -> Package {
        let version = try await attempt("Send page") { () async throws(UploadTrouble) in try await client.loadSendPage() }
        if version != UschovnaWire.knownScriptVersion {
            uschovnaLog.warning("The send page loads uschovna.js \(version ?? "(none found)", privacy: .public), not \(UschovnaWire.knownScriptVersion, privacy: .public); the protocol may have changed")
        }
        let names = items.map(\.name)
        let hostName = try await attempt("package_target") { () async throws(UploadTrouble) in
            try await client.packageTarget(names: names, totalBytes: totalBytes)
        }
        var host = client.site
        if let hostName {
            if let candidate = client.uploadOrigin(named: hostName) {
                if candidate != client.site, try await uploadHostAnswers(candidate) { host = candidate }
            } else {
                uschovnaLog.warning("package_target named an upload host that isn't a host name; using the site")
            }
        }
        let code = try await attempt("zalozeni_zasilky") { () async throws(UploadTrouble) in
            try await client.createPackage(on: host, sender: sender)
        }
        uschovnaLog.info("Created package \(code, privacy: .private) on \(host, privacy: .public) for \(self.items.count, privacy: .public) file(s), \(self.totalBytes, privacy: .public) bytes, from \(self.sender, privacy: .private)")
        return Package(host: host, code: code)
    }

    /// `test_xss`: the page uses the upload host when it answers, and falls back to the site on any
    /// failure. Only a lost network is waited out, so a dropped Wi-Fi doesn't move the upload.
    private func uploadHostAnswers(_ host: WebOrigin) async throws(UploadTrouble) -> Bool {
        while true {
            do {
                try await client.testUploadHost(host)
                return true
            } catch {
                switch error {
                case .cancelled:
                    throw error
                case .network(let urlError) where isOffline(urlError):
                    emit(.waitingForNetwork(sent: acknowledged))
                    try await waitForNetwork()
                    try await pause(after: 1)
                    emit(.connecting(sent: acknowledged))
                default:
                    uschovnaLog.notice("Upload host \(host, privacy: .public) didn't pass test_xss (\(error.detail, privacy: .public)); using the site, as the page does")
                    return false
                }
            }
        }
    }

    /// Ends the package on the site and returns its link.
    private func finish() async throws(UploadTrouble) -> URL {
        guard let finishing = package else { throw .refused("No package to finish") }
        let code: String
        do {
            code = try await attempt("dokoncit") { () async throws(UploadTrouble) in
                try await client.finish(package: finishing.code)
            }
        } catch {
            if case .refused = error { package = nil }
            throw error
        }
        reportProgress(force: true)
        let built = client.packageLink(code: code)
        // The page goes to the built link; the package page it opens shows its sender a link to
        // share. That one wins when it plainly belongs to this package.
        let shown = await client.packagePageLink(code: code)
        let link: URL
        if let shown, shown.absoluteString.contains(code) || shown.absoluteString.contains(finishing.code) {
            link = shown
        } else {
            link = built
        }
        // Whether the two differ is what the first real upload has to settle, so that part is public.
        let comparison = shown == nil ? "shows no package link" : shown == built ? "shows the same link" : "shows a different link"
        uschovnaLog.info("Finished: the package page \(comparison, privacy: .public), and the \(link == built ? "built" : "shown", privacy: .public) one is shared; finish code \(code == finishing.code ? "matches" : "differs from", privacy: .public) the package code. Opened \(built.absoluteString, privacy: .private), shown \(shown?.absoluteString ?? "-", privacy: .private)")
        return link
    }

    // MARK: Retrying

    /// Runs one request until it succeeds, the way the page would keep at it but with an end:
    /// a lost network is waited out without limit (with `.waitingForNetwork`, then
    /// `.connecting`), while failures with the network up get `timing.maxAttempts` tries in all.
    /// Refusals, cancellation and unreadable files end it at once.
    private func attempt<T>(_ step: String, _ operation: () async throws(UploadTrouble) -> T) async throws(UploadTrouble) -> T {
        var failures = 0
        var offlineChecks = 0
        while true {
            do {
                return try await operation()
            } catch {
                switch error {
                case .cancelled, .refused, .local:
                    throw error
                case .server(let detail, let retry):
                    failures += 1
                    guard retry, failures < timing.maxAttempts else { throw error }
                    uschovnaLog.notice("\(detail, privacy: .public); trying again (\(failures, privacy: .public))")
                    try await pause(after: failures)
                case .network(let urlError):
                    emit(.waitingForNetwork(sent: acknowledged))
                    if isOffline(urlError) {
                        uschovnaLog.notice("\(step, privacy: .public) lost the network (URL error \(urlError.code.rawValue, privacy: .public)); waiting for it")
                        try await waitForNetwork()
                        failures = 0
                        offlineChecks += 1
                        try await pause(after: offlineChecks)
                    } else {
                        failures += 1
                        guard failures < timing.maxAttempts else { throw error }
                        uschovnaLog.notice("\(step, privacy: .public) failed with URL error \(urlError.code.rawValue, privacy: .public); trying again (\(failures, privacy: .public))")
                        try await pause(after: failures)
                    }
                    emit(.connecting(sent: acknowledged))
                }
            }
        }
    }

    /// No network at all, as opposed to a network that failed this once: the path is gone, or the
    /// system says there's no internet even though a path is up (a router with no line behind it).
    /// Waiting that out doesn't count as Úschovna failing.
    private func isOffline(_ error: URLError) -> Bool {
        if watch?.isOnline == false { return true }
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive: return true
        default: return false
        }
    }

    private func pause(after failures: Int) async throws(UploadTrouble) {
        let delays = timing.retryDelays
        guard !delays.isEmpty else { return }
        do {
            try await Task.sleep(for: delays[min(max(failures, 1), delays.count) - 1])
        } catch {
            throw .cancelled
        }
    }

    private func waitForNetwork() async throws(UploadTrouble) {
        do {
            try await watch?.waitUntilOnline()
        } catch {
            throw .cancelled
        }
    }

    // MARK: Pieces

    /// The page sends `still_alive` before a chunk once 12 hours have passed since the package was
    /// created or the last one went out.
    private func keepAliveIfDue() async {
        guard let current = package, ContinuousClock.now - current.lastKeepAlive > timing.stillAliveInterval else { return }
        package?.lastKeepAlive = .now
        await client.stillAlive(package: current.code)
    }

    private func readChunk(of item: Item, offset: Int64, length: Int) async throws(UploadTrouble) -> Data {
        let data: Data
        do {
            data = try await FileChunks.read(item.url, offset: offset, length: length)
        } catch {
            throw .local("A file couldn't be read: \((error as NSError).domain) \((error as NSError).code)")
        }
        guard data.count == length else { throw .local("A file got shorter while it was being sent") }
        return data
    }

    /// Refuses, before anything is sent, what Úschovna's page wouldn't send as a free package.
    private func checkFiles() async throws(UploadTrouble) {
        guard !items.isEmpty else { throw .local("Nothing to send: Úschovna doesn't take empty files") }
        guard items.count <= UschovnaWire.maxFilesPerPackage else {
            throw .local("\(items.count) files are more than the \(UschovnaWire.maxFilesPerPackage) a package can hold")
        }
        guard totalBytes <= UschovnaWire.freePackageBytes else {
            throw .local("\(totalBytes) bytes are more than a free package can hold")
        }
        let sizes = await FileChunks.sizes(of: items.map(\.url))
        guard zip(items, sizes).allSatisfy({ $0.size == $1 }) else {
            throw .local("A file is missing or changed size since it was dropped")
        }
    }

    /// Bytes Úschovna has confirmed, across all the files.
    private var acknowledged: Int64 {
        guard let package else { return 0 }
        return items.prefix(package.fileIndex).reduce(0) { $0 + $1.size } + package.offset
    }

    private func emit(_ event: UploadEvent) {
        onEvent?(event)
    }

    /// At most one `.progress` per `timing.progressInterval`, except at the end of each file.
    private func reportProgress(force: Bool) {
        let now = ContinuousClock.now
        if !force, let last = lastProgressReport, now - last < timing.progressInterval { return }
        lastProgressReport = now
        emit(.progress(sent: acknowledged))
    }
}
