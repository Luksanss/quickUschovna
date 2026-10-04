// The Úschovna client's test harness: the app's real upload code, compiled with the app's
// concurrency settings by `run-tests.sh`, against `mock_server.py`. Nothing here talks to
// uschovna.cz.
//
// Usage: harness <site URL of the mock> [scenario names…]   (no names: all of them)

import Foundation

// MARK: Plumbing

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Failure(description: message()) }
}

let arguments = CommandLine.arguments.dropFirst()
let site: URL = {
    guard let argument = arguments.first, let url = URL(string: argument) else {
        print("usage: harness <mock site URL> [scenario…]")
        exit(2)
    }
    return url
}()
let selected = Set(arguments.dropFirst())
let scratch = FileManager.default.temporaryDirectory.appending(path: "uschovna-harness-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

/// The mock's control API.
enum Mock {
    static func control(_ command: [String: Any]) async throws {
        var request = URLRequest(url: site.appending(path: "__control"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        _ = try await URLSession.shared.data(for: request)
    }

    /// Clears everything and sets the faults and settings for one scenario.
    static func reset(rules: [[String: Any]] = [], settings: [String: Any] = [:]) async throws {
        let defaults: [String: Any] = ["slow_kbps": 0, "test_xss_fails": false, "no_upload_host": false, "link_style": "same"]
        try await control(["reset": true, "rules": rules, "settings": defaults.merging(settings) { $1 }])
    }

    static func rules(_ rules: [[String: Any]]) async throws {
        try await control(["rules": rules])
    }

    static func state() async throws -> MockState {
        let (data, _) = try await URLSession.shared.data(from: site.appending(path: "__state"))
        return MockState(raw: try JSONSerialization.jsonObject(with: data) as! [String: Any])
    }
}

struct MockState {
    let raw: [String: Any]
    var errors: [String] { raw["errors"] as? [String] ?? [] }
    var packages: [[String: Any]] { raw["packages"] as? [[String: Any]] ?? [] }
    var chunks: [[String: Any]] { raw["chunks"] as? [[String: Any]] ?? [] }
    var requests: [[String: Any]] { raw["requests"] as? [[String: Any]] ?? [] }
    var stillAlive: [[String: Any]] { raw["still_alive"] as? [[String: Any]] ?? [] }
    var aborted: [[String: Any]] { raw["aborted"] as? [[String: Any]] ?? [] }
    var sessions: [String] { raw["sessions"] as? [String] ?? [] }
    var targets: [[String: Any]] { raw["targets"] as? [[String: Any]] ?? [] }

    func requests(to endpoint: String) -> [[String: Any]] { requests.filter { $0["endpoint"] as? String == endpoint } }
    /// The stored copy of a file, by the name Úschovna has for it.
    func storedFile(named name: String) -> URL? {
        for package in packages {
            if let files = package["files"] as? [String: Any], let file = files[name] as? [String: Any],
               let path = file["path"] as? String { return URL(filePath: path) }
        }
        return nil
    }
}

/// A network the harness can take away.
nonisolated final class FakeNetwork: NetworkWatching {
    let waiters = NetworkWaiters()
    var isOnline: Bool { waiters.isOnline }
    func waitUntilOnline() async throws { try await waiters.wait() }
    func stop() { waiters.cancelAll() }
    func set(online: Bool) { waiters.setOnline(online) }
}

/// What a run reported, in order.
final class EventLog {
    private(set) var events: [UploadEvent] = []
    private(set) var times: [ContinuousClock.Instant] = []
    var onEvent: ((UploadEvent) -> Void)?

    func record(_ event: UploadEvent) {
        events.append(event)
        times.append(.now)
        onEvent?(event)
    }

    var progress: [Int64] { events.compactMap { if case .progress(let sent) = $0 { sent } else { nil } } }
    var connecting: [Int64] { events.compactMap { if case .connecting(let sent) = $0 { sent } else { nil } } }
    var waiting: [Int64] { events.compactMap { if case .waitingForNetwork(let sent) = $0 { sent } else { nil } } }
}

/// Short waits so the faults are quick to sit through. Slow-link scenarios use `slowTiming`, since
/// the kernel's socket buffers take a whole chunk at once and the request then looks idle until the
/// answer, which at 400 KiB/s is seconds.
let quickTiming = UschovnaTiming(
    requestTimeout: 1.5,
    retryDelays: [.milliseconds(50), .milliseconds(100), .milliseconds(100), .milliseconds(200)],
    stillAliveInterval: .seconds(43_200),
    progressInterval: .milliseconds(100))

var slowTiming: UschovnaTiming {
    var timing = quickTiming
    timing.requestTimeout = 15
    return timing
}

func service(timing: UschovnaTiming = quickTiming, network: FakeNetwork? = FakeNetwork()) -> UschovnaService {
    if let network {
        return UschovnaService(baseURL: site, timing: timing, network: { network })
    }
    return UschovnaService(baseURL: site, timing: timing, network: { SystemNetworkWatch() })
}

func run(_ session: UploadSession, _ log: EventLog) async -> Result<URL, any Error> {
    do {
        return .success(try await session.run { log.record($0) })
    } catch {
        return .failure(error)
    }
}

// MARK: Files

func makeRandomFile(_ name: String, bytes: Int) async throws -> UploadFile {
    try await writeRandomFile(name, bytes: bytes, in: scratch)
}

@concurrent func writeRandomFile(_ name: String, bytes: Int, in scratch: URL) async throws -> UploadFile {
    let url = scratch.appending(path: UUID().uuidString).appending(path: name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var generator = SystemRandomNumberGenerator()
    var data = Data(count: bytes)
    data.withUnsafeMutableBytes { buffer in
        for index in stride(from: 0, to: bytes, by: 8) {
            var value = generator.next()
            withUnsafeBytes(of: &value) { word in
                for offset in 0..<min(8, bytes - index) { buffer[index + offset] = word[offset] }
            }
        }
    }
    try data.write(to: url)
    return UploadFile(url: url, name: name, size: Int64(bytes))
}

/// A sparse file of `bytes` with a few marked bytes, so offsets past 2 GiB and 4 GiB matter.
func makeSparseFile(_ name: String, bytes: Int64) async throws -> UploadFile {
    try await writeSparseFile(name, bytes: bytes, in: scratch)
}

@concurrent func writeSparseFile(_ name: String, bytes: Int64, in scratch: URL) async throws -> UploadFile {
    let url = scratch.appending(path: name)
    FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(bytes))
    for (offset, marker) in [(Int64(0), "start"), (Int64(1) << 31 - 3, "two gib"), ((Int64(1) << 32) + 5, "four gib"),
                             (bytes - 9, "the end!!")] {
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data(marker.utf8))
    }
    return UploadFile(url: url, name: name, size: bytes)
}

@concurrent func sameBytes(_ a: URL, _ b: URL) async throws -> Bool {
    let left = try FileHandle(forReadingFrom: a)
    let right = try FileHandle(forReadingFrom: b)
    defer { try? left.close(); try? right.close() }
    while true {
        let one = try left.read(upToCount: 8 << 20) ?? Data()
        let two = try right.read(upToCount: 8 << 20) ?? Data()
        if one != two { return false }
        if one.isEmpty { return true }
    }
}

/// Every file arrived whole, under its composed name, and the mock saw nothing off-protocol.
func expectDelivered(_ files: [UploadFile], _ state: MockState) async throws {
    try expect(state.errors.isEmpty, "the mock recorded protocol errors: \(state.errors)")
    for file in files where file.size > 0 {
        let name = file.name.precomposedStringWithCanonicalMapping
        guard let stored = state.storedFile(named: name) else { throw Failure(description: "\(name) never arrived") }
        try expect(try await sameBytes(file.url, stored), "\(name) arrived with different bytes")
    }
}

func expectOrderly(_ log: EventLog, total: Int64) throws {
    try expect(log.connecting.first == 0, "the first event isn't .connecting(sent: 0): \(log.events.prefix(3))")
    try expect(log.progress == log.progress.sorted(), "progress went backwards")
    try expect(log.progress.last == total, "the last progress is \(log.progress.last ?? -1), not \(total)")
}

func linkFromMock(_ state: MockState) -> URL? {
    (state.raw["links"] as? [String])?.last.flatMap(URL.init(string:))
}

// MARK: Scenarios

var scenarios: [(String, () async throws -> Void)] = []

scenarios.append(("small file", {
    try await Mock.reset()
    let file = try await makeRandomFile("hello.txt", bytes: 3000)
    let log = EventLog()
    let session = service(network: nil).makeSession(files: [file], sender: "name@example.com")
    let link = try await run(session, log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expectOrderly(log, total: 3000)
    try expect(link == linkFromMock(state), "returned \(link), the mock handed out \(String(describing: linkFromMock(state)))")
    let order = state.requests.map { $0["endpoint"] as? String ?? "?" }
    try expect(order == ["page", "package_target", "test_xss", "create", "ajax_upload", "finish", "package_page"],
               "requests went \(order)")
    try expect(state.packages.first?["role"] as? String == "upload", "the package wasn't created on the upload host")
    let chunk = state.chunks.first ?? [:]
    try expect(chunk["content_type"] as? String == "application/octet-stream", "chunk Content-Type \(chunk["content_type"] ?? "none")")
    // Run again after success: the same link, no new requests.
    let again = try await run(session, EventLog()).get()
    try expect(again == link, "a second run returned another link")
    try expect(try await Mock.state().requests.count == state.requests.count, "a second run after success made requests")
}))

scenarios.append(("each session has its own cookie", {
    try await Mock.reset()
    let one = try await makeRandomFile("one.txt", bytes: 10)
    let two = try await makeRandomFile("two.txt", bytes: 20)
    _ = try await run(service().makeSession(files: [one], sender: "name@example.com"), EventLog()).get()
    _ = try await run(service().makeSession(files: [two], sender: "name@example.com"), EventLog()).get()
    let state = try await Mock.state()
    try await expectDelivered([one, two], state)
    let finishes = Set(state.requests(to: "finish").compactMap { $0["cookie"] as? String })
    try expect(state.sessions.count == 2 && finishes.count == 2, "two sessions shared a PHPSESSID")
}))

scenarios.append(("several files, one empty", {
    try await Mock.reset()
    let files = [
        try await makeRandomFile("a.bin", bytes: 2048),
        try await makeRandomFile("empty.txt", bytes: 0),
        try await makeRandomFile("b.bin", bytes: 1_500_000),
        try await makeRandomFile("c.bin", bytes: 300_000),
    ]
    let log = EventLog()
    _ = try await run(service().makeSession(files: files, sender: "name@example.com"), log).get()
    let state = try await Mock.state()
    try await expectDelivered(files, state)
    try expectOrderly(log, total: 2048 + 1_500_000 + 300_000)
    let names = state.targets.first?["filenames"] as? [String]
    try expect(names == ["a.bin", "b.bin", "c.bin"], "package_target got \(names ?? [])")
    let firstChunks = state.chunks.filter { $0["usize"] as? Int == 0 }.map { $0["name"] as? String ?? "" }
    try expect(firstChunks == ["a.bin", "b.bin", "c.bin"], "files went in the order \(firstChunks)")
}))

scenarios.append(("non-ASCII names", {
    try await Mock.reset()
    let decomposed = "Úschovna Ž.mov".decomposedStringWithCanonicalMapping
    let files = [
        try await makeRandomFile(decomposed, bytes: 5000),
        try await makeRandomFile("žluťoučký kůň & co+50% (1).txt", bytes: 7000),
        try await makeRandomFile("📦 balík #2;x=y.bin", bytes: 9000),
    ]
    _ = try await run(service().makeSession(files: files, sender: "name@example.com"), EventLog()).get()
    let state = try await Mock.state()
    try await expectDelivered(files, state)
    let names = state.targets.first?["filenames"] as? [String] ?? []
    try expect(names.first == "Úschovna Ž.mov" && names.first?.unicodeScalars.count == 14,
               "the decomposed name wasn't sent composed: \(names.first.map { Array($0.unicodeScalars) } ?? [])")
}))

scenarios.append(("multi-GB sparse file", {
    try await Mock.reset()
    let size: Int64 = 4_600_000_000
    let file = try await makeSparseFile("big sparse.img", bytes: size)
    let log = EventLog()
    // A heartbeat on the main actor: if reading 10 MiB chunks or sending them ever ran there, it
    // would miss beats.
    let heartbeat = Task { () -> Duration in
        var longest = Duration.zero
        var last = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
            longest = max(longest, ContinuousClock.now - last)
            last = .now
        }
        return longest
    }
    let started = ContinuousClock.now
    _ = try await run(service().makeSession(files: [file], sender: "name@example.com"), log).get()
    let elapsed = ContinuousClock.now - started
    heartbeat.cancel()
    let longestGap = await heartbeat.value
    try expect(longestGap < .milliseconds(100), "the main actor went \(longestGap) without running")
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expectOrderly(log, total: size)
    let sizes = state.chunks.compactMap { $0["csize"] as? Int }
    try expect(sizes.first == 104_858, "the first chunk was \(sizes.first ?? 0) bytes, the page sends 104858")
    try expect(sizes.allSatisfy { $0 <= 10_485_760 }, "a chunk was bigger than 10 MiB")
    try expect(sizes.dropFirst().dropLast().allSatisfy { $0 == 10_485_760 }, "a fast link didn't get 10 MiB chunks")
    var expected: Int64 = 0
    for chunk in state.chunks {
        let start = (chunk["usize"] as? NSNumber)?.int64Value
        try expect(start == expected, "chunk \(chunk["n"] ?? 0) started at \(start ?? -1), not \(expected)")
        expected += (chunk["csize"] as? NSNumber)?.int64Value ?? 0
    }
    let seconds = Double(elapsed.components.seconds) + 1
    try expect(Double(log.progress.count) <= seconds * 10 + 5, "\(log.progress.count) progress events in \(elapsed)")
    print("    \(state.chunks.count) chunks in \(elapsed), \(log.progress.count) progress events, longest main-actor gap \(longestGap)")
}))

scenarios.append(("dropped connection and lost answer", {
    // 30 MB starts as 104858 bytes, then 10 MiB chunks. The third request is dropped halfway;
    // its second try (re-measured from the smallest chunk) is stored but its answer is lost, so
    // the same offset is sent a third time.
    try await Mock.reset(rules: [["kind": "drop", "at": 3], ["kind": "lose_response", "at": 4]])
    let file = try await makeRandomFile("drop.bin", bytes: 30_000_000)
    let log = EventLog()
    _ = try await run(service().makeSession(files: [file], sender: "name@example.com"), log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expectOrderly(log, total: 30_000_000)
    try expect(log.waiting.count >= 2, "expected .waitingForNetwork twice, got \(log.waiting)")
    try expect(log.connecting.count == 1 + log.waiting.count, "each wait should end in .connecting: \(log.events)")
    try expect(state.packages.count == 1, "the package was started over")
    try expect(state.chunks.contains { $0["rewound"] as? Bool == true }, "the lost answer's chunk wasn't sent again from its offset")
}))

scenarios.append(("offline, then back", {
    try await Mock.reset(rules: [["kind": "drop", "at": 2]])
    let file = try await makeRandomFile("offline.bin", bytes: 2_000_000)
    let network = FakeNetwork()
    let log = EventLog()
    var requestsWhileOffline = -1
    var offlineAt: ContinuousClock.Instant?
    log.onEvent = { event in
        switch event {
        case .progress where offlineAt == nil:
            network.set(online: false)
            offlineAt = .now
        case .waitingForNetwork:
            Task {
                defer { network.set(online: true) }
                guard let before = try? await Mock.state().requests(to: "ajax_upload").count else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard let after = try? await Mock.state().requests(to: "ajax_upload").count else { return }
                requestsWhileOffline = after - before
            }
        default: break
        }
    }
    _ = try await run(service(network: network).makeSession(files: [file], sender: "name@example.com"), log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(log.waiting == [104_858], "expected one wait at 104858 bytes, got \(log.waiting)")
    try expect(log.connecting == [0, 104_858], "expected to resume at 104858, got \(log.connecting)")
    try expect(requestsWhileOffline == 0, "\(requestsWhileOffline) chunk request(s) went out while offline")
    try expect(state.packages.count == 1, "the package was started over")
}))

scenarios.append(("stalled chunk times out", {
    try await Mock.reset(rules: [["kind": "stall", "at": 2, "seconds": 4]])
    let file = try await makeRandomFile("stall.bin", bytes: 500_000)
    let log = EventLog()
    let started = ContinuousClock.now
    _ = try await run(service().makeSession(files: [file], sender: "name@example.com"), log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(ContinuousClock.now - started >= .seconds(1.4), "finished before the request timeout could fire")
    try expect(log.waiting.count == 1, "expected one .waitingForNetwork for the stall, got \(log.waiting)")
    let retried = state.chunks.dropFirst().first ?? [:]
    try expect(retried["usize"] as? Int == 104_858 && retried["csize"] as? Int == 104_858,
               "the chunk after the timeout wasn't sent again from its offset at the smallest size: \(retried)")
}))

scenarios.append(("server errors are retried", {
    try await Mock.reset(rules: [["kind": "http500", "at": 2, "times": 3], ["kind": "bad_json", "at": 5]])
    let file = try await makeRandomFile("retry.bin", bytes: 800_000)
    let log = EventLog()
    _ = try await run(service().makeSession(files: [file], sender: "name@example.com"), log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.requests(to: "ajax_upload").count == state.chunks.count + 4, "expected four failed chunk requests")
    try expect(log.waiting.isEmpty, "server errors aren't network loss")
}))

scenarios.append(("server keeps failing, then Try Again resumes", {
    try await Mock.reset(rules: [["kind": "http500", "at": 3, "times": 1000]])
    let file = try await makeRandomFile("resume.bin", bytes: 25_000_000)
    let session = service().makeSession(files: [file], sender: "name@example.com")
    let first = await run(session, EventLog())
    guard case .failure(UploadFailure.notAnswering(let detail)) = first else {
        throw Failure(description: "expected UploadFailure.notAnswering, got \(first)")
    }
    try expect(detail.contains("HTTP 500"), "the detail doesn't say what failed: \(detail)")
    var state = try await Mock.state()
    try expect(state.requests(to: "ajax_upload").count == 2 + quickTiming.maxAttempts,
               "expected \(quickTiming.maxAttempts) attempts at chunk 3, got \(state.requests(to: "ajax_upload").count - 2)")
    let acknowledged = state.chunks.reduce(0) { $0 + ($1["csize"] as? Int ?? 0) }
    try await Mock.rules([])
    let log = EventLog()
    _ = try await run(session, log).get()
    state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.packages.count == 1, "Try Again created a new package")
    try expect(log.connecting.first == Int64(acknowledged), "Try Again started at \(log.connecting.first ?? -1), not \(acknowledged)")
    let resumedAt = state.chunks[2]["usize"] as? Int ?? -1
    try expect(resumedAt == acknowledged, "the first chunk after Try Again started at \(resumedAt)")
}))

scenarios.append(("fatal res, then Try Again starts over", {
    try await Mock.reset(rules: [["kind": "fatal", "at": 2]])
    let file = try await makeRandomFile("fatal.bin", bytes: 400_000)
    let session = service().makeSession(files: [file], sender: "name@example.com")
    let first = await run(session, EventLog())
    guard case .failure(UploadFailure.notAnswering(let detail)) = first else {
        throw Failure(description: "expected UploadFailure.notAnswering, got \(first)")
    }
    try expect(detail.contains("res=0"), "the detail doesn't name the res: \(detail)")
    try await Mock.rules([])
    let log = EventLog()
    _ = try await run(session, log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.packages.count == 2, "expected a second package")
    try expect(log.connecting.first == 0, "a new package should start at 0")
}))

scenarios.append(("refused resume starts a new package", {
    try await Mock.reset(rules: [["kind": "http500", "at": 2, "times": 1000]])
    let file = try await makeRandomFile("refused.bin", bytes: 600_000)
    let session = service().makeSession(files: [file], sender: "name@example.com")
    guard case .failure = await run(session, EventLog()) else { throw Failure(description: "the first run should fail") }
    try await Mock.rules([["kind": "fatal", "at": 1]])
    let log = EventLog()
    _ = try await run(session, log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.packages.count == 2, "expected a second package after the refusal")
    try expect(log.connecting == [104_858, 0], "expected .connecting at the old offset, then at 0: \(log.connecting)")
}))

scenarios.append(("create refused", {
    try await Mock.reset(rules: [["kind": "refuse", "endpoint": "create"]])
    let file = try await makeRandomFile("create.bin", bytes: 100)
    let result = await run(service().makeSession(files: [file], sender: "name@example.com"), EventLog())
    guard case .failure(UploadFailure.notAnswering(let detail)) = result else {
        throw Failure(description: "expected UploadFailure.notAnswering, got \(result)")
    }
    try expect(detail.contains("zalozeni_zasilky"), "detail: \(detail)")
    try expect(try await Mock.state().requests(to: "create").count == 1, "a refusal shouldn't be retried")
}))

scenarios.append(("finish fails, Try Again only finishes", {
    try await Mock.reset(rules: [["kind": "http500", "endpoint": "finish", "times": 1000]])
    let file = try await makeRandomFile("finish.bin", bytes: 300_000)
    let session = service().makeSession(files: [file], sender: "name@example.com")
    guard case .failure = await run(session, EventLog()) else { throw Failure(description: "the first run should fail") }
    let chunksBefore = try await Mock.state().chunks.count
    try await Mock.rules([])
    let log = EventLog()
    _ = try await run(session, log).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.chunks.count == chunksBefore, "Try Again sent chunks again")
    try expect(log.connecting == [300_000], "Try Again should start at the end: \(log.connecting)")
}))

scenarios.append(("cancellation", {
    try await Mock.reset(settings: ["slow_kbps": 300])
    let file = try await makeRandomFile("cancel.bin", bytes: 8_000_000)
    let session = service(timing: slowTiming).makeSession(files: [file], sender: "name@example.com")
    let log = EventLog()
    let task = Task { try await session.run { log.record($0) } }
    while log.progress.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
    try await Task.sleep(for: .milliseconds(300))
    let cancelled = ContinuousClock.now
    task.cancel()
    let result = await task.result
    let took = ContinuousClock.now - cancelled
    guard case .failure(let error) = result, error is CancellationError else {
        throw Failure(description: "expected CancellationError, got \(result)")
    }
    try expect(took < .seconds(1), "cancelling took \(took)")
    // At 300 KiB/s the chunk in flight needs seconds more; returning in under one means it was
    // abandoned. Nothing more may go out after it.
    let requests = try await Mock.state().requests.count
    try await Task.sleep(for: .milliseconds(1500))
    let state = try await Mock.state()
    try expect(state.requests.count == requests, "requests went out after the cancel")
    try expect(state.requests(to: "finish").isEmpty, "a cancelled upload was finished")
}))

scenarios.append(("slow link sizes chunks like the page", {
    try await Mock.reset(settings: ["slow_kbps": 400])
    let file = try await makeRandomFile("slow.bin", bytes: 2_600_000)
    _ = try await run(service(timing: slowTiming).makeSession(files: [file], sender: "name@example.com"), EventLog()).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    let sizes = state.chunks.compactMap { $0["csize"] as? Int }
    // 400 KiB/s is 409600 bytes a second; the page sends five seconds' worth next.
    try expect(sizes.count >= 2 && (1_500_000...2_400_000).contains(sizes[1]), "chunk sizes \(sizes)")
    print("    chunk sizes at 400 KiB/s: \(sizes)")
}))

scenarios.append(("still_alive during a long upload", {
    try await Mock.reset(settings: ["slow_kbps": 1000])
    let file = try await makeRandomFile("alive.bin", bytes: 2_500_000)
    var timing = slowTiming
    timing.stillAliveInterval = .milliseconds(50)
    _ = try await run(service(timing: timing).makeSession(files: [file], sender: "name@example.com"), EventLog()).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    let code = state.packages.first?["code"] as? String
    try expect(!state.stillAlive.isEmpty && state.stillAlive.allSatisfy { $0["code"] as? String == code },
               "expected still_alive with the package code: \(state.stillAlive)")
}))

scenarios.append(("test_xss fails: the site takes the upload", {
    try await Mock.reset(settings: ["test_xss_fails": true])
    let file = try await makeRandomFile("fallback.bin", bytes: 250_000)
    _ = try await run(service().makeSession(files: [file], sender: "name@example.com"), EventLog()).get()
    let state = try await Mock.state()
    try await expectDelivered([file], state)
    try expect(state.packages.first?["role"] as? String == "www", "the package wasn't created on the site")
    try expect(state.requests(to: "ajax_upload").allSatisfy { $0["role"] as? String == "www" && $0["cookie"] is String },
               "chunks didn't go to the site with its cookie")
}))

scenarios.append(("the link the package page shows", {
    for (style, expectShown) in [("canonical", true), ("anchor", true), ("foreign", false), ("unrelated", false), ("none", false)] {
        try await Mock.reset(settings: ["link_style": style])
        let file = try await makeRandomFile("link.txt", bytes: 10)
        let link = try await run(service().makeSession(files: [file], sender: "name@example.com"), EventLog()).get()
        let built = try require(linkFromMock(try await Mock.state()))
        if expectShown {
            try expect(link != built && link.absoluteString.hasPrefix(built.absoluteString), "\(style): got \(link)")
        } else {
            try expect(link == built, "\(style): got \(link), expected \(built)")
        }
    }
}))

scenarios.append(("nothing to send", {
    try await Mock.reset()
    let empty = try await makeRandomFile("empty.txt", bytes: 0)
    let big = UploadFile(url: try await makeRandomFile("big.txt", bytes: 1).url, name: "big.txt", size: 33_000_000_000)
    for files in [[empty], [big]] {
        let result = await run(service().makeSession(files: files, sender: "name@example.com"), EventLog())
        guard case .failure(UploadFailure.notAnswering) = result else {
            throw Failure(description: "expected a failure, got \(result)")
        }
    }
    try expect(try await Mock.state().requests.isEmpty, "requests went out for nothing to send")
}))

// MARK: Run

func require<T>(_ value: T?) throws -> T {
    guard let value else { throw Failure(description: "missing value") }
    return value
}

var failed: [String] = []
for (name, scenario) in scenarios where selected.isEmpty || selected.contains(name) {
    let started = ContinuousClock.now
    do {
        try await scenario()
        print("PASS  \(name)  (\(ContinuousClock.now - started))")
    } catch {
        failed.append(name)
        print("FAIL  \(name): \(error)")
    }
}
print(failed.isEmpty ? "\nAll scenarios passed." : "\n\(failed.count) failed: \(failed.joined(separator: ", "))")
exit(failed.isEmpty ? 0 : 1)
