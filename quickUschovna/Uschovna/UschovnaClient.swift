import Foundation
import os

/// What went wrong with one request, sorted by what the upload should do about it.
nonisolated enum UploadTrouble: Error {
    case cancelled
    /// The request didn't get through: offline, dropped mid-chunk, timed out. Wait for the network
    /// and send the same request again.
    case network(URLError)
    /// Úschovna answered, but not usefully: a 5xx, or a page where JSON should be. `retry` is false
    /// when asking again won't help, like a 4xx.
    case server(String, retry: Bool)
    /// Úschovna said no in its own protocol (`status` isn't 1, a chunk's `res` isn't 1 or 2). The
    /// package can't be continued.
    case refused(String)
    /// A file couldn't be read, or changed while it was being sent.
    case local(String)

    /// The URL loading codes that mean the network, not Úschovna, failed.
    init(_ error: URLError) {
        switch error.code {
        case .cancelled:
            self = .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .callIsActive,
             .dataNotAllowed, .secureConnectionFailed, .cannotLoadFromNetwork:
            self = .network(error)
        default:
            self = .server("URL error \(error.code.rawValue)", retry: true)
        }
    }

    /// For logs and `UploadFailure.notAnswering`. Never holds file names, the sender or the
    /// package code.
    var detail: String {
        switch self {
        case .cancelled: "Cancelled"
        case .network(let error): "Network: URL error \(error.code.rawValue)"
        case .server(let detail, _): detail
        case .refused(let detail): detail
        case .local(let detail): detail
        }
    }
}

/// A scheme, host and port: what the browser compares to decide whether a request is cross-origin.
nonisolated struct WebOrigin: Sendable, Equatable, CustomStringConvertible {
    let scheme: String
    let host: String
    let port: Int?

    init?(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        self.scheme = scheme
        self.host = host
        let defaultPort = scheme == "https" ? 443 : 80
        port = url.port == defaultPort ? nil : url.port
    }

    /// "https://www.uschovna.cz"
    var description: String { "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "") }

    func url(_ pathAndQuery: String) -> URL { URL(string: description + pathAndQuery)! }
}

/// The answer to one chunk.
nonisolated enum ChunkReply: Sendable {
    /// `res=1`: continue from `offset`, the size Úschovna now has, quoting `tmp` with the next chunk.
    case next(offset: Int64, tmp: String?)
    /// `res=2`: the file is complete.
    case fileDone
    /// Any other `res`, which the page treats as fatal.
    case refused(String)
}

/// The requests Úschovna's send page makes, with the headers its browser would send, over a
/// `URLSession` of the upload's own. The session is ephemeral, so the `PHPSESSID` cookie the page
/// load sets lives with this one upload and goes back with every request to the site, but never
/// to the upload host: the page's cross-origin XHRs don't send credentials, so neither does this.
final class UschovnaClient {
    let site: WebOrigin
    /// The send page, which is the `Referer` of everything the page does.
    let pageURL: URL
    private let session: URLSession
    private let userAgent: String

    init(site: URL, requestTimeout: TimeInterval) {
        self.site = WebOrigin(site)!
        pageURL = self.site.url("/poslat-zasilku")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // An idle timeout: how long a request may go without a byte moving. A stall shorter than
        // this is a slow link, not a failure.
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        // The upload waits for the network itself, so it can say so.
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        userAgent = "quickUschovna/\(version) (macOS; +https://github.com/Luksanss/quickUschovna)"
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: The protocol, in the page's order

    /// Loads the send page, as a browser does before anything else: it sets the `PHPSESSID` that
    /// the site's later calls carry. Returns the `uschovna.js` version the page names.
    func loadSendPage() async throws(UploadTrouble) -> String? {
        let (data, response) = try await send(navigation(to: pageURL, from: nil), step: "Send page")
        try check(response, step: "Send page")
        return UschovnaWire.scriptVersion(inPage: String(decoding: data, as: UTF8.self))
    }

    /// `POST /ajax/package_target/` on the site, with the files' names and total size. Returns the
    /// host the package should be uploaded to, or nil for the site itself.
    func packageTarget(names: [String], totalBytes: Int64) async throws(UploadTrouble) -> String? {
        let fields = names.map { ("filenames[]", $0) } + [("size", String(totalBytes))]
        let request = ajax(site, "/ajax/package_target/", fields)
        let object = try await json(request, step: "package_target")
        // `void 0 === s.status || 1 != s.status` fails it: a status must be there, and loosely 1.
        guard UschovnaWire.looselyEquals(object["status"], 1) else {
            throw .refused("package_target answered status \(UschovnaWire.describe(object["status"]))")
        }
        return object["name"] as? String
    }

    /// `POST {host}/ajax/test_xss`, which the page uses to learn whether it may talk to the upload
    /// host from its own origin. Anything but JSON in a 2xx makes the page fall back to the site;
    /// there's no CORS here, so the answer is all that's checked.
    func testUploadHost(_ host: WebOrigin) async throws(UploadTrouble) {
        let request = ajax(host, "/ajax/test_xss", [("test", "test")])
        let (data, response) = try await send(request, step: "test_xss")
        try check(response, step: "test_xss")
        guard let answer = UschovnaWire.json(data) else {
            throw .server("test_xss answered something that isn't JSON", retry: false)
        }
        // The page's failed call returns "error", and it checks with `==`, so that answer fails too.
        guard !UschovnaWire.isJavaScriptError(answer) else { throw .server("test_xss answered \"error\"", retry: false) }
    }

    /// `POST {host}/ajax/zalozeni_zasilky`: creates the package with the page's form as this app
    /// fills it, a sender and nothing else, and returns its code.
    func createPackage(on host: WebOrigin, sender: String) async throws(UploadTrouble) -> String {
        let fields = [
            ("sender_mail", sender),
            // `package_recipients[]` would come here; with no recipients jQuery writes nothing.
            ("message", ""),
            ("premium_checkbox", "0"),
            ("vice_moznosti", "1"),
            ("mail_subject", UschovnaWire.mailSubject),
            ("language_to", UschovnaWire.mailLanguage),
        ]
        let object = try await json(ajax(host, "/ajax/zalozeni_zasilky", fields), step: "zalozeni_zasilky")
        // `1 == e.status`, then `0 != code`.
        guard UschovnaWire.looselyEquals(object["status"], 1), let code = UschovnaWire.code(object["code"]) else {
            throw .refused("zalozeni_zasilky answered status \(UschovnaWire.describe(object["status"])) without a package code")
        }
        return code
    }

    /// `POST {host}/ajax/ajax_upload/{ms}`: one chunk of one file as the raw body, described by the
    /// page's `X_*` headers. Returns the answer and how long it took, for the next chunk's size.
    func uploadChunk(on host: WebOrigin, package: String, name: String, fileSize: Int64, offset: Int64,
                     tmp: String, body: Data) async throws(UploadTrouble) -> (ChunkReply, Duration) {
        var request = URLRequest(url: host.url("/ajax/ajax_upload/\(Self.milliseconds())"))
        request.httpMethod = "POST"
        let sameOrigin = host == site
        identify(&request, sameOrigin: sameOrigin)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        // The page sets this one itself on the upload XHR, cross-origin or not.
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        // A browser sends a typeless Blob with no Content-Type; URLSession would add a form type,
        // which a PHP server would try to parse as fields. Bytes are bytes.
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(package, forHTTPHeaderField: "X_PACKAGE")
        request.setValue(UschovnaWire.encodeURIComponent(name), forHTTPHeaderField: "X_NAME")
        request.setValue(String(fileSize), forHTTPHeaderField: "X_SIZE")
        request.setValue(String(offset), forHTTPHeaderField: "X_USIZE")
        request.setValue(String(body.count), forHTTPHeaderField: "X_CSIZE")
        request.setValue(tmp, forHTTPHeaderField: "X_TMP")
        // A body on a data task, not an upload task: upload tasks add the resumable-upload draft's
        // `Upload-Complete` headers, which no browser sends.
        request.httpBody = body

        let started = ContinuousClock.now
        let (data, response) = try await send(request, step: "ajax_upload")
        let elapsed = ContinuousClock.now - started
        // The page retries anything but a 200, whatever it is.
        guard response.statusCode == 200 else {
            throw .server("ajax_upload answered HTTP \(response.statusCode)", retry: true)
        }
        // The page sends the same chunk again when the answer isn't JSON.
        guard let object = UschovnaWire.jsonObject(data) else {
            throw .server("ajax_upload answered something that isn't JSON (\(data.count) bytes)", retry: true)
        }
        // `1 == a.res`, then `2 == a.res`.
        if UschovnaWire.looselyEquals(object["res"], 1) {
            guard let next = UschovnaWire.integer(object["usize"]) else {
                throw .server("ajax_upload answered res 1 without a usable usize", retry: false)
            }
            return (.next(offset: next, tmp: UschovnaWire.text(object["tmp"])), elapsed)
        }
        if UschovnaWire.looselyEquals(object["res"], 2) { return (.fileDone, elapsed) }
        return (.refused("ajax_upload answered res \(UschovnaWire.describe(object["res"]))"), elapsed)
    }

    /// `POST /ajax/still_alive` on the site, which the page sends once every 12 hours of uploading.
    /// The page ignores the answer, so this does too.
    func stillAlive(package: String) async {
        let request = ajax(site, "/ajax/still_alive", [("package_code", package)])
        do {
            let (_, response) = try await send(request, step: "still_alive")
            uschovnaLog.info("still_alive answered HTTP \(response.statusCode, privacy: .public)")
        } catch {
            uschovnaLog.info("still_alive failed: \(error.detail, privacy: .public)")
        }
    }

    /// `POST /ajax/zalozeni_zasilky` with `dokoncit`, on the site even when the files went to an
    /// upload host. Returns the code the page then opens as `/zasilka/{code}`.
    func finish(package: String) async throws(UploadTrouble) -> String {
        let fields = [("package_code", package), ("dokoncit", "true")]
        let object = try await json(ajax(site, "/ajax/zalozeni_zasilky", fields), step: "dokoncit")
        // `void 0 !== e.status && 1 == e.status && 0 != e.code`.
        guard UschovnaWire.looselyEquals(object["status"], 1), let code = UschovnaWire.code(object["code"]) else {
            throw .refused("Finishing answered status \(UschovnaWire.describe(object["status"])) without a code")
        }
        return code
    }

    /// The page's redirect target, `{site}/zasilka/{code}`.
    func packageLink(code: String) -> URL {
        let segment = code.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? code
        return site.url("/zasilka/\(segment)")
    }

    /// Opens the package page, as the browser does after finishing, and returns the link it shows
    /// its sender to share, if it shows one on Úschovna's own domain. Nil on any failure: the
    /// built link is a good answer too.
    func packagePageLink(code: String) async -> URL? {
        var request = navigation(to: packageLink(code: code), from: pageURL)
        request.timeoutInterval = 20
        guard let (data, response) = try? await send(request, step: "Package page"),
              (200..<300).contains(response.statusCode),
              let link = UschovnaWire.packageLink(inPage: String(decoding: data, as: UTF8.self)),
              let origin = WebOrigin(link), isUschovna(origin)
        else { return nil }
        return link
    }

    /// The upload host `package_target` named, with the site's scheme as the page uses
    /// `location.protocol`.
    func uploadOrigin(named name: String) -> WebOrigin? {
        guard UschovnaWire.isHostName(name), let url = URL(string: "\(site.scheme)://\(name)") else { return nil }
        return WebOrigin(url)
    }

    // MARK: Requests

    /// A page load: what a browser sends when it goes to `url`, from `referrer` if it followed one.
    private func navigation(to url: URL, from referrer: URL?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referrer { request.setValue(referrer.absoluteString, forHTTPHeaderField: "Referer") }
        return request
    }

    /// A jQuery `$.ajax` POST as the page's `ajax_dotaz` makes it: the form in the body, a
    /// millisecond timestamp as the query to dodge caches, JSON asked for. jQuery adds
    /// `X-Requested-With` only on same-origin requests.
    private func ajax(_ origin: WebOrigin, _ path: String, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: origin.url("\(path)?\(Self.milliseconds())"))
        request.httpMethod = "POST"
        request.httpBody = UschovnaWire.formBody(fields)
        let sameOrigin = origin == site
        identify(&request, sameOrigin: sameOrigin)
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if sameOrigin { request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With") }
        return request
    }

    /// What a browser on the send page adds to an XHR: its origin, a referrer (the whole page
    /// URL on its own origin, just the origin elsewhere), and cookies only on its own origin.
    private func identify(_ request: inout URLRequest, sameOrigin: Bool) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(site.description, forHTTPHeaderField: "Origin")
        request.setValue(sameOrigin ? pageURL.absoluteString : site.description + "/", forHTTPHeaderField: "Referer")
        request.httpShouldHandleCookies = sameOrigin
    }

    private func json(_ request: URLRequest, step: String) async throws(UploadTrouble) -> [String: Any] {
        let (data, response) = try await send(request, step: step)
        try check(response, step: step)
        guard let object = UschovnaWire.jsonObject(data) else {
            throw .server("\(step) answered something that isn't JSON (\(data.count) bytes)", retry: true)
        }
        return object
    }

    private func send(_ request: URLRequest, step: String) async throws(UploadTrouble) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Task.isCancelled ? .cancelled : UploadTrouble(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw Task.isCancelled ? .cancelled : .server("\(step) failed: \(type(of: error))", retry: true)
        }
        guard let http = response as? HTTPURLResponse else { throw .server("\(step): not an HTTP answer", retry: true) }
        return (data, http)
    }

    /// jQuery calls 2xx a success. Server errors, timeouts and rate limits may pass; other 4xx won't.
    private func check(_ response: HTTPURLResponse, step: String) throws(UploadTrouble) {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        throw .server("\(step) answered HTTP \(status)", retry: status >= 500 || status == 408 || status == 429)
    }

    private func isUschovna(_ origin: WebOrigin) -> Bool {
        let domain = site.host.hasPrefix("www.") ? String(site.host.dropFirst(4)) : site.host
        return origin.host == site.host || origin.host == domain || origin.host.hasSuffix("." + domain)
    }

    private static func milliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
}
