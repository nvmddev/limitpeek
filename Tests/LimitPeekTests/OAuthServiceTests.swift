import Foundation
import Testing
@testable import LimitPeek

struct OAuthServiceTests {
    @Test func parsesCodeWithMatchingState() throws {
        #expect(try OAuthService.parseCallback(" code#state \n", expectedState: "state") == "code")
    }

    @Test func acceptsBareCode() throws {
        #expect(try OAuthService.parseCallback("code", expectedState: "state") == "code")
    }

    @Test func authorizationURLCarriesTheChallengeAndState() throws {
        let pkce = PKCE()
        let url = OAuthService().authorizationURL(pkce: pkce)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })

        #expect(url.host() == "claude.com")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == pkce.state)
        #expect(query["scope"] == "user:profile")
        #expect(query["redirect_uri"] == OAuth.redirectURI)
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
