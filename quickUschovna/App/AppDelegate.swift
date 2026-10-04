import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Shared with the extensions of `AppDelegate` that receive files from outside, like the Quick Action.
    let model = AppModel(service: AppDelegate.uploadService(), store: AppDelegate.settingsStore())
    private var statusItem: StatusItemController?
    private var surfaces: SurfacePresenter?
    private var dragMonitor: DragMonitor?
    #if DEBUG
    private var debugControl: DebugControl?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = StatusItemController(model: model)
        self.statusItem = statusItem
        surfaces = SurfacePresenter(model: model, statusItem: statusItem)
        let dragMonitor = DragMonitor(model: model, statusItem: statusItem)
        dragMonitor.start()
        self.dragMonitor = dragMonitor
        #if DEBUG
        debugControl = DebugControl(model: model)
        #endif
    }

    /// Úschovna itself, or in Debug builds with `--simulate`, a stand-in that sends nothing.
    private static func uploadService() -> UploadService {
        #if DEBUG
        if let simulated = SimulatedUploadService(arguments: CommandLine.arguments) { return simulated }
        #endif
        return UschovnaService()
    }

    /// The real settings, or with `--simulate`, a separate set that a simulated run can't spoil.
    private static func settingsStore() -> SettingsStore {
        #if DEBUG
        if CommandLine.arguments.contains("--simulate"), let defaults = UserDefaults(suiteName: "com.luksanss.quickUschovna.simulated") {
            return SettingsStore(defaults: defaults,
                                 historyURL: FileManager.default.temporaryDirectory.appending(path: "quickUschovna-simulated-history.json"))
        }
        #endif
        return .standard
    }
}
