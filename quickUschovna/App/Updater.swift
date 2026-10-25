import Sparkle

/// Check for Updates… (docs/spec.md § Updates). Sparkle starts the first time it's chosen, and
/// never checks by itself: Info.plist turns its automatic checks off.
final class Updater: NSObject, SPUUpdaterDelegate {
    private let model: AppModel
    private var controller: SPUStandardUpdaterController?
    /// Install and Relaunch, held until nothing is sending.
    private var pendingRelaunch: (() -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    /// Shows Sparkle's window: up to date, a newer version to install, or what went wrong.
    func checkForUpdates() {
        let controller = controller ?? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.checkForUpdates(nil)
    }

    /// Install and Relaunch quits the app, which would cut off what's sending. So it waits until the
    /// queue is empty, every package sent or cancelled, and then goes ahead.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !model.queue.isEmpty else { return false }
        pendingRelaunch = installHandler
        // The app's `observe` (Observe.swift), not NSObject's key-value one.
        quickUschovna.observe { [weak self] in
            guard let self, self.model.queue.isEmpty, let relaunch = self.pendingRelaunch else { return }
            self.pendingRelaunch = nil
            relaunch()
        }
        return true
    }
}
