import AppKit

/// Notices a file drag anywhere on screen and opens the drop zone for it (`AppModel.drag`), then
/// closes the zone when the drag ends. Only file drags count: dragging text or a window doesn't
/// open it.
///
/// Watches other apps' mouse events with global monitors, which need no permission (only key events
/// would). A drag session writes to the drag pasteboard, so a change in its count since the mouse
/// went down means a drag has started.
final class DragMonitor {
    private let model: AppModel
    private var monitors: [Any] = []
    private var changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var isDragging = false
    private var measuring: Task<Void, Never>?
    /// A drop on the zone or the icon is delivered just after the mouse goes up, so the zone stays
    /// open this long to receive it.
    private static let dropGrace: Duration = .milliseconds(300)

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        add(.leftMouseDown) { $0.changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount }
        add(.leftMouseDragged) { $0.dragged() }
        add(.leftMouseUp) { $0.released() }
    }

    private func add(_ type: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (DragMonitor) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: type, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }) {
            monitors.append(monitor)
        }
    }

    private func dragged() {
        guard !isDragging else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != changeCountAtMouseDown else { return }
        // Seen once per drag, files or not.
        changeCountAtMouseDown = pasteboard.changeCount
        let urls = FileDrop.fileURLs(in: pasteboard)
        guard !urls.isEmpty else { return }
        isDragging = true
        model.drag = DragSummary(label: Format.packageLabel(for: urls), bytes: nil)
        // Until the drop, the files aren't ours to read. A file's size is metadata, which macOS
        // allows, but measuring a folder means listing it, and in Desktop, Documents or Downloads
        // that would raise a permission prompt in the middle of the drag. So a drag with folders
        // shows its label only; the drop itself grants access, and the size is checked then.
        guard !urls.contains(where: FileMeasure.isDirectory) else { return }
        measuring = Task {
            let bytes = await FileMeasure.totalSize(of: urls)
            guard !Task.isCancelled, self.isDragging else { return }
            self.model.drag?.bytes = bytes
        }
    }

    private func released() {
        guard isDragging else { return }
        isDragging = false
        measuring?.cancel()
        Task {
            try? await Task.sleep(for: Self.dropGrace)
            guard !self.isDragging else { return }
            self.model.drag = nil
            self.model.isDragOverIcon = false
        }
    }
}
