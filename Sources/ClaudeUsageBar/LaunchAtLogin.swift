import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` so the UI can read and toggle
/// launch-at-login without touching the framework directly.
enum LaunchAtLogin {

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app for launch at login.
    /// Returns the new enabled state; throws if the system call fails.
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
        return isEnabled
    }
}
