import Foundation
import ServiceManagement

/// Pure mapping of `SMAppService.Status`, so the UI can be driven by a value
/// that is testable without touching ServiceManagement.
enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    /// The user wants the app at login, even if macOS still needs approval.
    var isEnabled: Bool { self == .enabled || self == .requiresApproval }

    var needsApproval: Bool { self == .requiresApproval }

    /// Whether the app will actually launch at login right now.
    var isEffective: Bool { self == .enabled }
}

/// Launch-at-login via SMAppService, so there is no helper bundle to install.
@MainActor
enum LoginItem {
    static var status: LaunchAtLoginStatus {
        LaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
