import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Atmora opens when you log in."
        case .requiresApproval:
            return "Approve Atmora in System Settings › General › Login Items."
        case .notFound:
            return "Launch at login is available in the packaged app."
        case .notRegistered:
            return "Atmora will not open automatically."
        @unknown default:
            return "Launch at login is unavailable."
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            try service.unregister()
        }
    }
}
