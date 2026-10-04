import Foundation

/// A file ready to send: folders are already zipped by the time a package gets here.
struct UploadFile: Sendable, Equatable {
    let url: URL
    /// The name Úschovna shows, e.g. "Raw footage.zip".
    let name: String
    let size: Int64
}

/// What a running upload reports to the queue, on the main actor.
enum UploadEvent: Sendable, Equatable {
    /// Creating the package on Úschovna, or picking it up again; `sent` is where it resumes.
    case connecting(sent: Int64)
    /// Bytes Úschovna has acknowledged so far, across all of the package's files.
    case progress(sent: Int64)
    /// The network went away. The session waits for it and resumes from `sent` on its own.
    case waitingForNetwork(sent: Int64)
}

/// Why an upload stopped for good, as far as the user is concerned.
enum UploadFailure: Error, Sendable, Equatable {
    /// Úschovna is down, refused the package, or answered in a way the client doesn't understand.
    /// Shown as "Úschovna isn’t answering", with Try Again.
    case notAnswering(detail: String)
}

/// One package's upload. `run` can be called again after a failure, and continues from the last
/// acknowledged byte while Úschovna still has the package.
protocol UploadSession: AnyObject {
    /// Uploads the files and returns the package's link. Network loss doesn't end it: it reports
    /// `.waitingForNetwork` and resumes by itself. Throws `UploadFailure` when Úschovna fails, and
    /// `CancellationError` when the calling task is cancelled. Must not block the main actor.
    func run(onEvent: @escaping @MainActor (UploadEvent) -> Void) async throws -> URL
}

/// Makes upload sessions. The real one is `UschovnaService`; Debug builds also have a simulated one.
protocol UploadService {
    func makeSession(files: [UploadFile], sender: String) -> UploadSession
}
