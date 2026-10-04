import Foundation
import Network
import Synchronization

/// Whether the Mac can reach the network at all, so an upload that lost its connection knows to
/// wait instead of counting failed attempts against Úschovna. A protocol so the test harness can
/// take the network away on cue.
nonisolated protocol NetworkWatching: AnyObject, Sendable {
    /// True while there's a usable path, and before the first answer from the system.
    var isOnline: Bool { get }
    /// Returns as soon as there's a usable path; at once if there already is one. Throws
    /// `CancellationError` when the calling task is cancelled.
    func waitUntilOnline() async throws
    /// Stops watching. Anyone still waiting gets `CancellationError`.
    func stop()
}

/// `NWPathMonitor`, for one run of an upload.
nonisolated final class SystemNetworkWatch: NetworkWatching {
    private let monitor = NWPathMonitor()
    private let waiters = NetworkWaiters()

    init() {
        monitor.pathUpdateHandler = { [waiters] path in
            waiters.setOnline(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.luksanss.quickUschovna.network", qos: .utility))
    }

    var isOnline: Bool { waiters.isOnline }

    func waitUntilOnline() async throws { try await waiters.wait() }

    func stop() {
        monitor.cancel()
        waiters.cancelAll()
    }
}

/// Tasks waiting for the network, and whether it's there. Shared by the real watch and the test
/// harness's fake one, because getting cancellation right around a continuation is the fiddly part.
nonisolated final class NetworkWaiters: Sendable {
    private struct State {
        var online = true
        var waiting: [UUID: CheckedContinuation<Void, any Error>] = [:]
    }

    private let state = Mutex(State())

    var isOnline: Bool { state.withLock { $0.online } }

    func setOnline(_ online: Bool) {
        let resumed: [CheckedContinuation<Void, any Error>] = state.withLock { state in
            state.online = online
            guard online else { return [] }
            defer { state.waiting.removeAll() }
            return Array(state.waiting.values)
        }
        resumed.forEach { $0.resume() }
    }

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Cancellation is checked under the lock, so a cancel that lands between here and
                // the handler below can't leave this continuation waiting forever.
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if state.online { return .success(()) }
                    state.waiting[id] = continuation
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let continuation = state.withLock { $0.waiting.removeValue(forKey: id) }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func cancelAll() {
        let all: [CheckedContinuation<Void, any Error>] = state.withLock { state in
            defer { state.waiting.removeAll() }
            return Array(state.waiting.values)
        }
        all.forEach { $0.resume(throwing: CancellationError()) }
    }
}
