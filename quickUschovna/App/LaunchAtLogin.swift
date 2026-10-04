import Foundation
import ServiceManagement
import os

/// Launch at Login through `SMAppService`. The system owns the state; nothing is stored here.
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "launchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // Expected in dev: a build in DerivedData may not be allowed to register.
            let error = error as NSError
            logger.error("Launch at Login failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
        let status = service.status
        logger.info("Launch at Login status: \(status.rawValue, privacy: .public)")
        // Registered, but the user has to approve it before it counts; show them where.
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
