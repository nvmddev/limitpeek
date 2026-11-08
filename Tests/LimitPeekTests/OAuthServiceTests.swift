import Testing
@testable import LimitPeek

struct OAuthServiceTests {
    @Test func parsesCodeWithMatchingState() throws {
        let callback = try OAuthService.parseCallback(" code#state \n", expectedState: "state")
        #expect(callback.code == "code")
        #expect(callback.state == "state")
    }

    @Test func acceptsBareCode() throws {
        let callback = try OAuthService.parseCallback("code", expectedState: "state")
        #expect(callback.code == "code")
        #expect(callback.state == "state")
    }

    @Test func rejectsMismatchedState() {
        #expect {
            try OAuthService.parseCallback("code#other", expectedState: "state")
        } throws: { error in
            guard case OAuthError.stateMismatch = error else { return false }
            return true
        }
    }

    @Test func rejectsEmptyCode() {
        #expect(throws: OAuthError.self) {
            try OAuthService.parseCallback("   ", expectedState: "state")
        }
    }
}
