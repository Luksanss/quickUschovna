import Foundation

// Placeholder so the scaffold builds. The Quick Action replaces it.

/// Finder's Quick Actions › Send with Úschovna: hands the selected items to the app.
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: nil)
    }
}
