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
