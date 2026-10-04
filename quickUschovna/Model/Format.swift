import Foundation

/// The text formats the design uses (`design/prototype/quickUschovna v1.dc.html`). Sizes come from
/// `ByteCountFormatter` and dates from `DateFormatter`, so they follow the system's locale.
enum Format {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "Oct 18", for "Expires Oct 18".
    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// "a few seconds left", "25 sec left", "3 min left", "1 hr 5 min left", as the prototype's
    /// `fmtLeft`.
    static func timeLeft(seconds: Double) -> String {
        if seconds < 5 { return "a few seconds left" }
        if seconds < 60 { return "\(Int((seconds / 5).rounded(.up)) * 5) sec left" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min left" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded())
        return "\(hours) hr \(minutes) min left"
    }

    /// The days left on a link in Recent: "13 days left", "expires tomorrow", "expires today".
    static func daysLeft(until expires: Date, now: Date = .now) -> (text: String, isSoon: Bool) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: expires)).day ?? 0
        switch days {
        case ...0: return ("expires today", true)
        case 1: return ("expires tomorrow", true)
        default: return ("\(days) days left", false)
        }
    }

    /// Splits a long name so the end, with its extension, never truncates: the head gets the
    /// ellipsis and the tail stays whole. Names of 18 characters or fewer aren't split. The
    /// prototype's `split`.
    static func splitName(_ name: String) -> (head: String, tail: String) {
        guard name.count > 18 else { return (name, "") }
        let characters = Array(name)
        let dot = characters.lastIndex(of: ".")
        let tailLength = max(8, dot.map { $0 > 0 ? characters.count - $0 + 5 : 8 } ?? 8)
        return (String(characters.dropLast(tailLength)), String(characters.suffix(tailLength)))
    }

    /// A package's label: a file's name, a folder's name plus ".zip", or "4 files".
    static func packageLabel(for items: [URL]) -> String {
        guard items.count == 1, let item = items.first else { return "\(items.count) files" }
        return item.hasDirectoryPath || isDirectory(item) ? item.lastPathComponent + ".zip" : item.lastPathComponent
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
