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

    /// Any JSON value, which is all `/ajax/test_xss` has to answer with.
    static func json(_ data: Data) -> Any? {
        var bytes = data[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return try? JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])
    }

    /// Whether the page's loose comparison `number == value` holds for a value from Úschovna's
    /// JSON. The page compares every `status` and `res` with `==`, so `true`, `"1"` and `1` all
    /// count as 1 (the real `package_target` answers `"status": true`), and `false`, `""` and
    /// `"0"` as 0. `null` and a missing value equal no number.
    static func looselyEquals(_ value: Any?, _ number: Double) -> Bool {
        javaScriptNumber(value) == number
    }

    /// JavaScript's `ToNumber` for what JSON can hold: booleans are 1 and 0, strings are parsed as
    /// JavaScript parses them (trimmed, empty is 0, hex with `0x`, anything else is NaN), an array
    /// becomes its joined text first. Nil for null, a missing value, and NaN.
    static func javaScriptNumber(_ value: Any?) -> Double? {
        switch value {
        case nil, is NSNull:
            return nil
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? 1 : 0
        case let number as NSNumber:
            return number.doubleValue.isNaN ? nil : number.doubleValue
        case let string as String:
            return javaScriptNumber(parsing: string)
        case let array as [Any]:
            // `[x] == 1` compares `String([x])`, which is `x`'s text; `[] == 0` holds.
            switch array.count {
            case 0: return 0
            case 1: return array[0] is [Any] || array[0] is [String: Any] ? nil : javaScriptNumber(parsing: javaScriptText(array[0]))
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func javaScriptNumber(parsing text: String) -> Double? {
        // JavaScript trims its whitespace and line terminators, NBSP and BOM included.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if trimmed.isEmpty { return 0 }
        if let match = trimmed.wholeMatch(of: /0[xX]([0-9a-fA-F]+)|0[oO]([0-7]+)|0[bB]([01]+)/) {
            let (digits, radix) = match.1.map { ($0, 16) } ?? match.2.map { ($0, 8) } ?? (match.3!, 2)
            return UInt64(digits, radix: radix).map { Double($0) }
        }
        switch trimmed {
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        guard trimmed.wholeMatch(of: /[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?/) != nil else { return nil }
        return Double(trimmed)
    }

    /// JavaScript's `String(x)` for a JSON scalar.
    private static func javaScriptText(_ value: Any) -> String {
        switch value {
        case is NSNull: ""
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue ? "true" : "false"
        case let number as NSNumber: number.stringValue
        case let string as String: string
        default: "\(value)"
        }
    }

    /// A JSON value as JSON would write it, for logs and failure details: `true`, `"1"`, `1`.
    static func describe(_ value: Any?) -> String {
        guard let value else { return "nothing" }
        if JSONSerialization.isValidJSONObject([value]),
           let data = try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8) {
            return String(text.dropFirst().dropLast())
        }
        return "\(value)"
    }

    /// A number the page uses as a number, like `usize`: a JSON number, or a string of digits.
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

    /// A package code. The page checks `0 != e.code`, loosely, so `0`, `"0"`, `""` and `false`
    /// all mean "no package"; a code that isn't text or a number isn't one either.
    static func code(_ value: Any?) -> String? {
        guard let text = text(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !looselyEquals(value, 0)
        else { return nil }
        return text
    }

    /// `"error" == answer`: the page's test for a failed synchronous call, which also holds for an
    /// answer that is the JSON string `"error"` (or `["error"]`).
    static func isJavaScriptError(_ value: Any?) -> Bool {
        switch value {
        case let string as String: string == "error"
        case let array as [Any]: array.count == 1 && (array[0] as? String) == "error"
        default: false
        }
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
