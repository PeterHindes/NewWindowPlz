import Foundation
import ServiceManagement

enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Off"
        case .notFound:
            return "Not found"
        case .requiresApproval:
            return "Needs approval in System Settings"
        @unknown default:
            return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
        Log.app.info("Launch at login set to \(enabled, privacy: .public), status=\(self.statusDescription, privacy: .public)")
    }
}
