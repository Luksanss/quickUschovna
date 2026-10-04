import Foundation

/// Úschovna's limits for a free package, as its price list stated them on 2026-10-04.
enum Limits {
    /// "Free packages are limited to 30 GB." A drop over this is refused before anything uploads.
    static let freePackageBytes: Int64 = 30_000_000_000
    /// How long Úschovna keeps a free package, and so how long its link stays in Recent.
    static let retentionDays = 14
}

/// One drop: one package on Úschovna, one link. The first package in `AppModel.queue` is the one
/// being worked on; the rest wait behind it.
struct UploadPackage: Identifiable, Equatable {
    enum Status: Equatable {
        /// Waiting behind another package, or about to start.
        case queued
        /// Zipping its folders into one archive each, before anything is sent.
        case zipping
        /// Creating the package on Úschovna, or picking it up again after a pause or a retry.
        case connecting
        case uploading
        /// The network went away; the upload continues from `sent` when it's back.
        case reconnecting
        /// Úschovna failed. The package stays queued until Try Again or cancel.
        case failed
    }

    let id: UUID
    /// What the user sees: the file's name, a folder's name plus ".zip", or "4 files".
    let label: String
    /// The items as dropped. Folders are zipped before upload.
    let items: [URL]
    /// Bytes to send. Before zipping it's the items' total; after, the zipped size.
    var bytes: Int64
    /// Bytes Úschovna has acknowledged.
    var sent: Int64 = 0
    var status: Status = .queued
    /// For "Zipping “Raw footage”…": the folder's name, or "2 folders".
    var zipName: String = ""
    var zipDone: Int64 = 0
    var zipTotal: Int64 = 0
    /// Smoothed upload speed, for "3 min left". Nil until there's enough to measure.
    var bytesPerSecond: Double?

    var fractionSent: Double { bytes > 0 ? min(1, Double(sent) / Double(bytes)) : 0 }
    var fractionZipped: Double { zipTotal > 0 ? min(1, Double(zipDone) / Double(zipTotal)) : 0 }
}

/// A sent package's link, kept in Recent until Úschovna deletes the package.
struct LinkRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let label: String
    let bytes: Int64
    let link: URL
    let sentAt: Date
    let expires: Date

    func isValid(at now: Date = .now) -> Bool { expires > now }
}

/// The bubble under the icon. Only one shows at a time; a new one replaces the old.
enum Bubble: Equatable {
    /// "Link copied". Stays about 3 s, longer while hovered; a click opens the link.
    case copied(label: String, bytes: Int64, expires: Date, link: URL)
    /// The first-run sender email field. `label` names what will be sent on Return.
    case email(label: String)
    /// "2.4 GB is too big". Nothing was uploaded.
    case tooBig(bytes: Int64)
    /// "Úschovna isn’t answering", with Try Again, for the package that failed.
    case failed(label: String, packageID: UUID)
}

/// A file drag in progress anywhere on screen, which opens the drop zone.
struct DragSummary: Equatable {
    /// As a package would be labelled: "report.mov", "Raw footage.zip", "4 files".
    var label: String
    /// Total size, or nil while folders are still being measured.
    var bytes: Int64?
    /// The drag is over the drop zone (or the icon), so the zone shows "Release to send".
    var isOver = false
    /// The drag has come near the menu-bar icon or onto it, so the drop zone is open until it ends.
    var isZoneOpen = false

    var isTooBig: Bool { (bytes ?? 0) > Limits.freePackageBytes }
}

/// What the menu-bar icon shows (`design/prototype/MenuBarIcon.dc.html`).
enum MenuBarIconState: Equatable {
    case idle
    /// The open box with the arrow pointing in. The drop zone's glyph while a drag is over it.
    case open
    /// A file drag is over the icon or the zone: the open box on an accent highlight.
    case target
    /// A dashed ring while folders are zipped.
    case zipping
    /// The ring fills clockwise with the fraction sent.
    case progress(Double)
    /// Reconnecting: the ring dims where it stopped, with pause bars.
    case paused(Double)
    /// A filled check for 2.5 s after a link is copied.
    case done
    /// A badge that stays until the user sees the error bubble or opens the panel.
    case error
}
