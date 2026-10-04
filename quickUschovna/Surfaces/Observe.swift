import Observation

/// Runs `apply` now, and again after every change to the observable state it read. How the AppKit
/// side (the status item, the surface windows) follows `AppModel`.
func observe(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        // Called before the change lands; run again once it has.
        Task { @MainActor in observe(apply) }
    }
}
