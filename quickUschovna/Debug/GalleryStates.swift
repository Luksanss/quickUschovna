#if DEBUG
import Foundation

/// One surface in one state, staged on a fresh model: what the Debug gallery renders. The states
/// and their names match the prototype captures they're compared with, and use the prototype's
/// sample data.
struct GalleryState {
    enum Surface {
        case dropZone, bubble, panel
    }

    let name: String
    let surface: Surface
    let stage: (AppModel) -> Void

    static let all: [GalleryState] = dropZone + bubble + panel

    // MARK: Drop zone

    private static let dropZone: [GalleryState] = [
        GalleryState(name: "zone-idle", surface: .dropZone) { $0.drag = DragSummary(label: "report.mov", bytes: 2_400_000_000) },
        GalleryState(name: "zone-over", surface: .dropZone) { $0.drag = DragSummary(label: "report.mov", bytes: 2_400_000_000, isOver: true) },
        GalleryState(name: "zone-toobig", surface: .dropZone) { $0.drag = DragSummary(label: "wedding-4k-master.mov", bytes: 45_000_000_000) },
        GalleryState(name: "zone-toobig-over", surface: .dropZone) {
            $0.drag = DragSummary(label: "wedding-4k-master.mov", bytes: 45_000_000_000, isOver: true)
        },
        GalleryState(name: "zone-files", surface: .dropZone) { $0.drag = DragSummary(label: "3 files", bytes: 2_103_312_000) },
        GalleryState(name: "zone-long", surface: .dropZone) { $0.drag = DragSummary(label: Sample.longName, bytes: 3_200_000_000) },
        GalleryState(name: "zone-measuring", surface: .dropZone) { $0.drag = DragSummary(label: "Raw footage.zip", bytes: nil) },
    ]

    // MARK: Bubble

    private static let bubble: [GalleryState] = [
        GalleryState(name: "bubble-copied", surface: .bubble) {
            $0.bubble = .copied(label: "report.mov", bytes: 2_400_000_000, expires: Sample.day(14), link: Sample.link)
        },
        GalleryState(name: "bubble-copied-hover", surface: .bubble) {
            $0.bubble = .copied(label: "report.mov", bytes: 2_400_000_000, expires: Sample.day(14), link: Sample.link)
            $0.isBubbleHovered = true
        },
        GalleryState(name: "bubble-copied-long", surface: .bubble) {
            $0.bubble = .copied(label: Sample.longName, bytes: 3_200_000_000, expires: Sample.day(14), link: Sample.link)
        },
        GalleryState(name: "bubble-email", surface: .bubble) { $0.bubble = .email(label: "report.mov") },
        GalleryState(name: "bubble-email-typed", surface: .bubble) {
            $0.bubble = .email(label: "report.mov")
            $0.emailDraft = Sample.email
        },
        GalleryState(name: "bubble-email-error", surface: .bubble) {
            $0.bubble = .email(label: "report.mov")
            $0.emailDraft = "jana.novak@"
            $0.emailError = Sample.badEmail
        },
        GalleryState(name: "bubble-toobig", surface: .bubble) { $0.bubble = .tooBig(bytes: 45_000_000_000) },
        GalleryState(name: "bubble-error", surface: .bubble) { $0.bubble = .failed(label: "report.mov", packageID: Sample.id(1)) },
        GalleryState(name: "bubble-error-long", surface: .bubble) { $0.bubble = .failed(label: Sample.longName, packageID: Sample.id(1)) },
    ]

    // MARK: Panel

    private static let panel: [GalleryState] = [
        GalleryState(name: "panel-empty", surface: .panel) { Sample.panel($0, history: []) },
        GalleryState(name: "panel-history", surface: .panel) { Sample.panel($0, history: Sample.fiveLinks) },
        GalleryState(name: "panel-copied", surface: .panel) {
            Sample.panel($0, history: Sample.fiveLinks)
            $0.copiedRecordID = Sample.fiveLinks[1].id
        },
        GalleryState(name: "panel-uploading", surface: .panel) {
            Sample.panel($0, history: Sample.fiveLinks)
            $0.queue = [Sample.package(1, "interview-raw.mov", 3_800_000_000, sent: 1_520_000_000, .uploading)]
        },
        GalleryState(name: "panel-uploading-measuring", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "interview-raw.mov", 3_800_000_000, sent: 1_520_000_000, .uploading, speed: nil)]
        },
        GalleryState(name: "panel-zipping", surface: .panel) {
            Sample.panel($0)
            var zipping = Sample.package(1, "3 files", 2_106_200_000, .zipping)
            zipping.zipName = "Raw footage"
            zipping.zipTotal = 2_100_000_000
            zipping.zipDone = 900_000_000
            $0.queue = [zipping, Sample.package(2, "b-roll.mov", 1_200_000_000, .queued)]
        },
        GalleryState(name: "panel-connecting", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, .connecting)]
        },
        GalleryState(name: "panel-resuming", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 1_440_000_000, .connecting)]
        },
        GalleryState(name: "panel-reconnecting", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 1_440_000_000, .reconnecting)]
        },
        GalleryState(name: "panel-failed", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 600_000_000, .failed)]
        },
        GalleryState(name: "panel-waiting", surface: .panel) {
            Sample.panel($0)
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 900_000_000, .uploading),
                        Sample.package(2, "b-roll.mov", 1_200_000_000, .queued)]
        },
        GalleryState(name: "panel-long", surface: .panel) {
            Sample.panel($0, history: [Sample.link(9, Sample.longName, 3_200_000_000, days: 14)] + Sample.twoLinks)
            $0.queue = [Sample.package(1, Sample.longName, 3_200_000_000, sent: 800_000_000, .uploading)]
        },
        GalleryState(name: "panel-scrolling", surface: .panel) {
            Sample.panel($0, history: Sample.fiveLinks + [Sample.link(6, "storyboard-final.key", 96_000_000, days: 1),
                                                         Sample.link(7, "interview-raw.mov", 3_800_000_000, days: 1)])
        },
        GalleryState(name: "panel-editing", surface: .panel) {
            Sample.panel($0)
            $0.isEditingEmail = true
            $0.emailDraft = Sample.email
        },
        GalleryState(name: "panel-editing-error", surface: .panel) {
            Sample.panel($0)
            $0.isEditingEmail = true
            $0.emailDraft = "jana.novak@"
            $0.emailError = Sample.badEmail
        },
        GalleryState(name: "panel-sender-unset", surface: .panel) {
            Sample.panel($0, history: [])
            $0.senderEmail = ""
            $0.launchAtLogin = false
        },
        GalleryState(name: "panel-quit-one", surface: .panel) {
            Sample.panel($0)
            $0.isConfirmingQuit = true
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 900_000_000, .uploading)]
        },
        GalleryState(name: "panel-quit-two", surface: .panel) {
            Sample.panel($0)
            $0.isConfirmingQuit = true
            $0.queue = [Sample.package(1, "report.mov", 2_400_000_000, sent: 900_000_000, .uploading),
                        Sample.package(2, "b-roll.mov", 1_200_000_000, .queued)]
        },
    ]
}

/// The prototype's sample data (`SC`, `HIST2`, `HIST5` in `quickUschovna v1.dc.html`).
enum Sample {
    static let email = "jana.novak@email.cz"
    static let badEmail = "That doesn’t look like an email address."
    static let longName = "Final_Final_v7_Prezentace_pro_klienta_Q4_2026_schvalena_verze_OPRAVDU_posledni.mov"
    static let link = URL(string: "https://www.uschovna.cz/zasilka/ABCDEFGHJKLMNPQR-STU/")!

    /// Midnight, `days` from today: how the prototype dates its links.
    static func day(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now))!
    }

    /// Stable ids, so a state can point at a row.
    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    static func link(_ number: Int, _ label: String, _ bytes: Int64, days: Int) -> LinkRecord {
        LinkRecord(id: id(100 + number), label: label, bytes: bytes, link: link,
                   sentAt: day(days - Limits.retentionDays), expires: day(days))
    }

    static let twoLinks = [link(1, "mix-master-v3.wav", 212_000_000, days: 13),
                           link(3, "drone-flight-02.mp4", 1_700_000_000, days: 6)]

    static let fiveLinks = [link(1, "mix-master-v3.wav", 212_000_000, days: 13),
                            link(2, "3 files", 640_000_000, days: 10),
                            link(3, "drone-flight-02.mp4", 1_700_000_000, days: 6),
                            link(4, "Holiday 2026.zip", 4_200_000_000, days: 3),
                            link(5, "site-plans.pdf", 48_000_000, days: 1)]

    /// A package as the prototype's `mkPkg`, uploading at its "300 MB/s" speed.
    static func package(_ number: Int, _ label: String, _ bytes: Int64, sent: Int64 = 0,
                        _ status: UploadPackage.Status, speed: Double? = 300_000_000) -> UploadPackage {
        UploadPackage(id: id(number), label: label, items: [], bytes: bytes, sent: sent, status: status,
                      bytesPerSecond: speed)
    }

    /// The panel open, with the prototype's defaults: a sender, Launch at Login on, two links.
    static func panel(_ model: AppModel, history: [LinkRecord] = twoLinks) {
        model.isPanelOpen = true
        model.senderEmail = email
        model.launchAtLogin = true
        model.history = history
    }
}
#endif
