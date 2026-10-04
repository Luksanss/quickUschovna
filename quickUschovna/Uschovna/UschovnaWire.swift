import Foundation
import os

nonisolated let uschovnaLog = Logger(subsystem: "com.luksanss.quickUschovna", category: "uschovna")

/// The parts of Úschovna's protocol that have to match its website byte for byte: how values are
/// encoded, how big each chunk is, how answers are read. All of it was read from the page's
/// `uschovna.js?v1.1.85` (`docs/uschovna-protocol.md`), and it's kept apart from the networking so
/// the mock server's tests and a future protocol change both have one place to look.
nonisolated enum UschovnaWire {
    /// The script version this client mirrors. The send page names it in its `<script>` tag; a
    /// different one is logged, because it's the first sign that the protocol may have moved.
    static let knownScriptVersion = "1.1.85"

    /// The page's first chunk of every upload is `0.1 * 1048576` = 104857.6 bytes, which
    /// `Blob.slice` rounds ([Clamp]) to 104858.
    static let firstChunkBytes = 104_858
    /// The page never sends more than 10 MiB at once.
    static let maxChunkBytes = 10_485_760
    /// 30 GiB (`30720 * 1048576`). Above this the page forces a paid Premium package, so the client
    /// never creates one: a free package must stay at or under it.
    static let freePackageBytes: Int64 = 32_212_254_720
    /// `maximalni_pocet_souboru_v_zasilce`.
    static let maxFilesPerPackage = 1000
    /// The page's defaults for the fields this app doesn't offer.
    static let mailSubject = "zásilka služby Úschovna.cz"
    static let mailLanguage = "cs"

    // MARK: Chunk size

    /// The size of the next chunk, from the speed of the last one, as the page's `UPL_CHUNK`: about
    /// five seconds' worth of data between 0.1 MiB/s and 2 MiB/s, 10 MiB above that, and the first
    /// chunk's size below it (or before anything was measured).
    static func chunkSize(afterSpeed bytesPerSecond: Int64) -> Int {
        if bytesPerSecond > 104_857 && bytesPerSecond <= 2_097_152 { return Int(5 * bytesPerSecond) }
        if bytesPerSecond > 2_097_152 { return maxChunkBytes }
        return firstChunkBytes
    }

    /// The page's speed measure (`jm`): the chunk's bytes over the whole milliseconds between
    /// sending it and the answer, at least one, rounded down.
    static func speed(bytes: Int, elapsed: Duration) -> Int64 {
        let parts = elapsed.components
        let milliseconds = max(1, parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
        return Int64(bytes) * 1000 / milliseconds
    }

    // MARK: Encoding

    /// JavaScript's `encodeURIComponent`: everything but ASCII letters, digits and `-_.!~*'()` is
    /// percent-encoded as UTF-8. `X_NAME` carries file names this way.
    static func encodeURIComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? ""
    }

    private static let uriComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    /// A form body the way the page's jQuery 1.x `$.param` writes one: `encodeURIComponent` on
    /// both sides, `&` between pairs, and `%20` turned into `+`. Array fields are passed as repeated
    /// `name[]` pairs; an empty array writes nothing at all.
    static func formBody(_ fields: [(String, String)]) -> Data {
        let pairs = fields.map { encodeURIComponent($0.0) + "=" + encodeURIComponent($0.1) }
        return Data(pairs.joined(separator: "&").replacingOccurrences(of: "%20", with: "+").utf8)
    }

    /// A file name as Úschovna should store it. macOS can hand out names in decomposed Unicode
    /// (NFD, "U" + combining acute); browsers on Windows send composed ones (NFC), so composing
    /// keeps "Úschovna Ž.mov" the same name however it reached the Mac.
    static func displayName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }

    // MARK: Reading answers

    /// The page asks jQuery for JSON, so an answer that doesn't parse is an error to it. PHP can
    /// print a byte order mark or whitespace around it; those are tolerated.
    static func jsonObject(_ data: Data) -> [String: Any]? {
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])) as? [String: Any]
    }

    /// Whether the answer parses as JSON at all, which is all `/ajax/test_xss` has to do.
    static func isJSON(_ data: Data) -> Bool {
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])) != nil
    }

    /// A number the page compares loosely (`1 == e.status`), so `1` and `"1"` both count.
    static func integer(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.int64Value
        case let string as String:
            return Int64(string.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    /// A value the page only passes along as text (`tmp`, a code), whether the JSON has it as a
    /// string or a number.
    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number.stringValue
        default: nil
        }
    }

    /// A package code. The page treats a missing one and `0` alike: no package.
    static func code(_ value: Any?) -> String? {
        guard let text = text(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text != "0"
        else { return nil }
        return text
    }

    /// `"1.1.85"` from the send page's `uschovna.js?v1.1.85`.
    static func scriptVersion(inPage html: String) -> String? {
        guard let match = html.firstMatch(of: /uschovna\.js\?v([0-9][0-9.]*)/) else { return nil }
        return String(match.1)
    }

    /// The upload host from `/ajax/package_target/`'s `name`: a host name with an optional port,
    /// nothing else, so an odd answer can't turn into an odd URL.
    static func isHostName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/) != nil
    }

    /// The link the package page shows its sender, in the element the page's script selects as
    /// `.l.data.package-link` to copy. Its text is the link, or holds an `<a>` with it; anything
    /// after the element closes isn't looked at.
    static func packageLink(inPage html: String) -> URL? {
        guard let marker = html.firstMatch(of: /class\s*=\s*["'][^"']*\bpackage-link\b[^"']*["'][^>]*>/) else {
            return nil
        }
        let after = html[marker.range.upperBound...]
        guard let content = after.prefixMatch(of: /(?:[^<]|<a\b[^>]*>|<\/a\s*>|<br\s*\/?>)*/),
              let link = content.0.firstMatch(of: /https?:\/\/[^\s"'<>]+/)
        else { return nil }
        return URL(string: String(link.0).replacingOccurrences(of: "&amp;", with: "&"))
    }
}
