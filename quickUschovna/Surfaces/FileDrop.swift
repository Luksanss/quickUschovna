import AppKit

/// Takes file drops for a window: the menu-bar icon's or the drop zone's. A window that has
/// registered for dragged types, and has no view registered for them, hands the dragging
/// destination calls to its delegate.
final class FileDrop: NSObject, NSWindowDelegate {
    /// The drag came over the target (true) or left it (false).
    var onHover: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    func attach(to window: NSWindow) {
        window.registerForDraggedTypes([.fileURL])
        window.delegate = self
    }

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (urls as? [URL]) ?? []
    }

    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !Self.fileURLs(in: sender.draggingPasteboard).isEmpty else { return [] }
        onHover(true)
        return .copy
    }

    @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(in: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    @objc func draggingExited(_ sender: NSDraggingInfo?) {
        onHover(false)
    }

    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(in: sender.draggingPasteboard)
        onHover(false)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
