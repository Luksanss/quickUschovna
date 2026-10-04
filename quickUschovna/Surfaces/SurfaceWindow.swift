import AppKit
import SwiftUI

/// A borderless, transparent panel for a surface that hangs from the menu-bar icon: the drop zone,
/// the bubble or the panel. The SwiftUI view draws the surface, its chrome and its shadow, so the
/// window itself draws nothing.
final class SurfaceWindow: NSPanel {
    /// Only a surface with a text field takes the keyboard: the panel, and the first-run bubble.
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Over normal windows, under menus, like the menu bar's own extras.
        level = .statusBar
        // On whichever Space is active, over full-screen apps too.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // quickUschovna is rarely the active app, so its surfaces mustn't hide when it isn't.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        // Hover in the bubble and the panel's rows works while another app is active.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// The surface itself: the window minus the room around it for the shadow.
    var surfaceFrame: NSRect {
        let insets = SurfaceMetrics.shadowInsets
        return NSRect(x: frame.minX + insets.leading, y: frame.minY + insets.bottom,
                      width: frame.width - insets.leading - insets.trailing,
                      height: frame.height - insets.top - insets.bottom)
    }

    /// The shadow is drawn by the view, so its faint pixels belong to the window and would catch
    /// clicks, even over the menu bar and the icon. Only the surface itself takes the mouse.
    func updateMouseHandling(at location: NSPoint = NSEvent.mouseLocation) {
        let ignores = !surfaceFrame.contains(location)
        if ignoresMouseEvents != ignores { ignoresMouseEvents = ignores }
    }
}

/// An `NSHostingView` that tells its window when the SwiftUI content's size changes, so the window
/// can grow or shrink downwards while its top stays under the menu bar.
final class SurfaceHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @MainActor @preconcurrency required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    /// Clicks reach the surface even when another app is active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
