import AppKit
import UniformTypeIdentifiers
import os

/// Finder's Quick Actions › Send with Úschovna. Finder hands over the selection as attachments, one
/// per file or folder; this resolves them to file URLs and opens them all at once with the app that
/// contains this extension, which gets them in `application(_:open:)` like a drop and sends them as
/// one package. It shows nothing itself.
///
/// Opening through Launch Services, rather than passing paths, is what lets the app (not sandboxed)
/// read items in Desktop, Documents and Downloads without a privacy prompt: like a double-click in
/// Finder, it counts as the user's choice. It also launches the app if it isn't running.
nonisolated final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = Request(context: context)
        Task { await request.run() }
    }
}

/// One run of the Quick Action. `NSExtensionContext` isn't `Sendable`; the request owns it alone and
/// only touches it from the task that finishes the request.
private nonisolated final class Request: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "quickAction")
    private let context: NSExtensionContext

    init(context: NSExtensionContext) {
        self.context = context
    }

    func run() async {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        var urls: [URL] = []
        for provider in providers {
            Self.logger.debug("Attachment types: \(provider.registeredTypeIdentifiers, privacy: .public)")
            if let url = await Self.fileURL(of: provider) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty, let app = Self.containingApp else {
            Self.logger.error("Nothing to send: \(urls.count) of \(providers.count) item(s) resolved")
            context.cancelRequest(withError: CocoaError(.fileReadUnknown))
            return
        }

        // Launch Services passes this extension's access to the items on to the app, so any access
        // that came as a security scope has to be held until they're open.
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        Self.logger.debug("Opening \(urls.count) item(s) with the app, \(scoped.count) under a security scope")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
            Self.logger.info("Handed \(urls.count) item(s) to the app")
            context.completeRequest(returningItems: nil)
        } catch {
            let error = error as NSError
            Self.logger.error("Opening the items with the app failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            context.cancelRequest(withError: error)
        }
    }

    /// `quickUschovna.app`, from `quickUschovna.app/Contents/PlugIns/QuickAction.appex`.
    private static var containingApp: URL? {
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    /// The file or folder behind one of Finder's attachments: its URL if the attachment offers one,
    /// otherwise the item itself opened in place. Never a copy, which the system deletes as soon as
    /// the load finishes, before the app could read it.
    private static func fileURL(of provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: NSURL.self) {
            let url = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url, url.isFileURL {
                return url
            }
        }
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .item) == true }) else {
            logger.error("An attachment is neither a file nor a folder: \(provider.registeredTypeIdentifiers, privacy: .public)")
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, isInPlace, error in
                if let url, isInPlace {
                    continuation.resume(returning: url)
                } else {
                    let error = error as NSError?
                    logger.error("An attachment can't be opened in place: \(type, privacy: .public) \(error?.domain ?? "", privacy: .public) \(error?.code ?? 0, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
