#if DEBUG
import Foundation

/// A stand-in for Úschovna in Debug builds, so the whole flow can be tried without sending
/// anything: `--simulate [MB/s]` on the command line. It reports progress at that speed and hands
/// back a link that's obviously fake. `--simulate-failure <fraction>` makes the first attempt of
/// every package fail at that point, so Try Again can be tried; `--simulate-offline <fraction>`
/// drops the "network" there for three seconds.
struct SimulatedUploadService: UploadService {
    let bytesPerSecond: Double
    let failAt: Double?
    let offlineAt: Double?

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--simulate") else { return nil }
        let speed = arguments.dropFirst(index + 1).first.flatMap(Double.init) ?? 300
        bytesPerSecond = speed * 1_000_000
        failAt = Self.value(after: "--simulate-failure", in: arguments)
        offlineAt = Self.value(after: "--simulate-offline", in: arguments)
    }

    private static func value(after flag: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        return arguments.dropFirst(index + 1).first.flatMap(Double.init)
    }

    func makeSession(files: [UploadFile], sender: String) -> UploadSession {
        SimulatedSession(total: files.reduce(0) { $0 + $1.size }, service: self)
    }
}

private final class SimulatedSession: UploadSession {
    private let total: Int64
    private let service: SimulatedUploadService
    private var sent: Int64 = 0
    private var hasFailed = false
    private var hasGoneOffline = false

    init(total: Int64, service: SimulatedUploadService) {
        self.total = total
        self.service = service
    }

    func run(onEvent: @escaping @MainActor (UploadEvent) -> Void) async throws -> URL {
        onEvent(.connecting(sent: sent))
        try await Task.sleep(for: .milliseconds(600))
        let step: TimeInterval = 0.1
        while sent < total {
            try await Task.sleep(for: .seconds(step))
            sent = min(total, sent + Int64(service.bytesPerSecond * step))
            let fraction = Double(sent) / Double(max(total, 1))
            if let failAt = service.failAt, !hasFailed, fraction >= failAt {
                hasFailed = true
                throw UploadFailure.notAnswering(detail: "Simulated failure")
            }
            if let offlineAt = service.offlineAt, !hasGoneOffline, fraction >= offlineAt {
                hasGoneOffline = true
                onEvent(.waitingForNetwork(sent: sent))
                try await Task.sleep(for: .seconds(3))
                onEvent(.connecting(sent: sent))
                try await Task.sleep(for: .milliseconds(600))
            }
            onEvent(.progress(sent: sent))
        }
        let code = String((0..<16).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })
        return URL(string: "https://www.uschovna.cz/zasilka/SIMULATED-\(code)/")!
    }
}
#endif
