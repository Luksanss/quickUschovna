import Foundation

/// Sends packages to Úschovna the way its website does (`docs/uschovna-protocol.md`): one package
/// per session, files one after another in chunks, one request at a time.
struct UschovnaService: UploadService {
    let baseURL: URL
    let timing: UschovnaTiming
    let makeNetworkWatch: @Sendable () -> any NetworkWatching

    /// `baseURL` is the site the page is loaded from; tests point it at the mock server.
    init(baseURL: URL = URL(string: "https://www.uschovna.cz")!) {
        self.init(baseURL: baseURL, timing: UschovnaTiming(), network: { SystemNetworkWatch() })
    }

    /// For the test harness: shorter waits, and a network it can take away.
    init(baseURL: URL, timing: UschovnaTiming, network: @escaping @Sendable () -> any NetworkWatching) {
        self.baseURL = baseURL
        self.timing = timing
        makeNetworkWatch = network
    }

    func makeSession(files: [UploadFile], sender: String) -> UploadSession {
        UschovnaSession(site: baseURL, files: files, sender: sender, timing: timing,
                        makeNetworkWatch: makeNetworkWatch)
    }
}

/// How patient an upload is. The defaults are the app's; the test harness shortens them.
nonisolated struct UschovnaTiming: Sendable {
    /// How long a request may go without a byte moving before it counts as a dropped connection.
    var requestTimeout: TimeInterval = 60
    /// The waits before each new attempt at a request that failed while the network was up, so
    /// there's one attempt more than there are waits. The page sends a failed chunk again every
    /// second, forever; this starts the same, backs off, and gives up after about a minute, when
    /// the user gets "Úschovna isn’t answering" and Try Again picks up where it stopped.
    var retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(15), .seconds(15)]
    /// The page's `still_alive_seconds`: a keep-alive once every 12 hours of uploading.
    var stillAliveInterval: Duration = .seconds(43_200)
    /// The least time between two `.progress` events.
    var progressInterval: Duration = .milliseconds(100)

    var maxAttempts: Int { retryDelays.count + 1 }
}
