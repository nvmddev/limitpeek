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

    @Test func disabledIsNotEnabled() {
        let status = LaunchAtLoginStatus.disabled

        #expect(!status.isEnabled)
        #expect(!status.needsApproval)
    }

    @Test func enabledIsEnabled() {
        let status = LaunchAtLoginStatus.enabled

        #expect(status.isEnabled)
        #expect(!status.needsApproval)
    }

    @Test func requiresApprovalIsEnabledButNeedsApproval() {
        let status = LaunchAtLoginStatus.requiresApproval

        #expect(status.isEnabled)
        #expect(status.needsApproval)
    }

    @Test func unavailableIsNotEnabled() {
        let status = LaunchAtLoginStatus.unavailable

        #expect(!status.isEnabled)
        #expect(!status.needsApproval)
    }
}
