import AppKit
import SwiftUI

/// Shows and hides the three surfaces that hang from the menu-bar icon, following `AppModel`: the
/// drop zone once a file drag comes near the icon, the bubble, and the panel. Each one starts 8 pt
/// left of the item and 6 pt below the menu bar, kept 8 pt inside the screen (`SurfaceMetrics`), on
/// the display whose menu bar holds the item.
final class SurfacePresenter {
    private let model: AppModel
    private let statusItem: StatusItemController
    private let zone: Surface<DropZoneView>
    private let bubble: Surface<BubbleView>
    private let panel: Surface<PanelView>
    private let zoneDrop = FileDrop()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var moveMonitors: [Any] = []

    init(model: AppModel, statusItem: StatusItemController) {
        self.model = model
        self.statusItem = statusItem
        zone = Surface { DropZoneView(model: model) }
        bubble = Surface { BubbleView(model: model) }
        panel = Surface { PanelView(model: model) }
        zone.place = { [weak self] window, size in self?.place(window, size: size) }
        bubble.place = zone.place
        panel.place = zone.place
        zoneDrop.onHover = { [weak model] over in model?.drag?.isOver = over }
        zoneDrop.onDrop = { [weak model] urls in model?.send(urls) }
        zoneDrop.attach(to: zone.window)
        installMonitors()
        observe { [weak self] in self?.update() }
    }

    private func update() {
        let isPanelOpen = model.isPanelOpen
        let showsBubble = model.bubble != nil && !isPanelOpen
        // The first-run bubble has the email field, so it takes the keyboard.
        var bubbleTakesKeys = false
        if case .email = model.bubble { bubbleTakesKeys = true }
        zone.setVisible(model.isDropZoneOpen, takesKeys: false)
        bubble.setVisible(showsBubble, takesKeys: bubbleTakesKeys)
        panel.setVisible(isPanelOpen, takesKeys: true)
    }

    private func place(_ window: SurfaceWindow, size: NSSize) {
        guard let anchor = statusItem.surfaceAnchor else { return }
        let insets = SurfaceMetrics.shadowInsets
        let frame = NSRect(x: anchor.left - insets.leading, y: anchor.top + insets.top - size.height,
                           width: size.width, height: size.height)
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    private func installMonitors() {
        // A click in another app closes the panel and any bubble that isn't "Link copied", as a
        // click on the prototype's desktop does. Clicks in our own windows never get here.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.clickedOutside() }
        }
        // Where the pointer is decides whether each surface's window takes the mouse
        // (`SurfaceWindow.updateMouseHandling`). Over another app the global monitor sees the
        // moves, over a surface the local one does; during a file drag only dragged events come.
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            for window in [self.zone.window, self.bubble.window, self.panel.window] where window.isVisible {
                window.updateMouseHandling()
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { _ in
            MainActor.assumeIsolated { update() }
        }) {
            moveMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            update()
            return event
        }) {
            moveMonitors.append(monitor)
        }
        // Esc reaches us while the panel or the first-run bubble has the keyboard.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            let somethingOpen = self.model.isPanelOpen || self.model.bubble != nil
            self.model.escape()
            return somethingOpen ? nil : event
        }
    }
}

/// One surface: its window and the SwiftUI view in it. A fresh hosting view each time it's shown,
/// so the view's appear animation plays.
@MainActor
final class Surface<Content: View> {
    let window = SurfaceWindow()
    var place: (SurfaceWindow, NSSize) -> Void = { _, _ in }
    private let makeContent: () -> Content
    private var host: SurfaceHostingView<Content>?

    init(content: @escaping () -> Content) {
        makeContent = content
    }

    func setVisible(_ visible: Bool, takesKeys: Bool) {
        window.allowsKey = takesKeys
        guard visible else {
            if host != nil {
                window.orderOut(nil)
                window.contentView = nil
                host = nil
            }
            return
        }
        if host == nil {
            let host = SurfaceHostingView(rootView: makeContent())
            host.onSizeChange = { [weak self] in
                // After SwiftUI has finished the layout that changed the size.
                Task { @MainActor in self?.resize() }
            }
            self.host = host
            window.contentView = host
            resize()
            window.orderFrontRegardless()
        }
        if takesKeys, !window.isKeyWindow {
            window.makeKey()
        } else if !takesKeys, window.isKeyWindow {
            window.resignKey()
        }
    }

    private func resize() {
        guard let host else { return }
        place(window, host.fittingSize)
        window.updateMouseHandling()
    }
}
