import ServiceManagement
import Testing
@testable import LimitPeek

/// Pure mapping tests: `SMAppService` itself is never touched, so no login item
/// is registered and no system settings are opened.
struct LaunchAtLoginStatusTests {
    @Test func mapsEveryAppServiceStatus() {
        #expect(LaunchAtLoginStatus(.notRegistered) == .disabled)
        #expect(LaunchAtLoginStatus(.enabled) == .enabled)
        #expect(LaunchAtLoginStatus(.requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginStatus(.notFound) == .unavailable)
    }

    @Test func disabledIsNeitherEnabledNorEffective() {
        let status = LaunchAtLoginStatus.disabled

        #expect(!status.isEnabled)
        #expect(!status.needsApproval)
        #expect(!status.isEffective)
    }

    @Test func enabledIsEnabledAndEffective() {
        let status = LaunchAtLoginStatus.enabled

        #expect(status.isEnabled)
        #expect(!status.needsApproval)
        #expect(status.isEffective)
    }

    @Test func requiresApprovalIsEnabledButNotEffective() {
        let status = LaunchAtLoginStatus.requiresApproval

        #expect(status.isEnabled)
        #expect(status.needsApproval)
        #expect(!status.isEffective)
    }

    @Test func unavailableIsNeitherEnabledNorEffective() {
        let status = LaunchAtLoginStatus.unavailable

        #expect(!status.isEnabled)
        #expect(!status.needsApproval)
        #expect(!status.isEffective)
    }
}
