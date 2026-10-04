import Foundation

// Placeholder so the scaffold builds. The real client replaces this file.

/// Sends packages to Úschovna the way its website does (`docs/handoff.md` § Findings).
struct UschovnaService: UploadService {
    func makeSession(files: [UploadFile], sender: String) -> UploadSession {
        PlaceholderSession()
    }
}

private final class PlaceholderSession: UploadSession {
    func run(onEvent: @escaping @MainActor (UploadEvent) -> Void) async throws -> URL {
        throw UploadFailure.notAnswering(detail: "Not implemented yet")
    }
}
