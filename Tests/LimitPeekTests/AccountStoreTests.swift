import Foundation
import Testing
@testable import LimitPeek

@MainActor
@Suite(.serialized)
struct AccountStoreTests {
    @Test func completingSignInFetchesUsage() async throws {
        let name = "LimitPeekTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            StubURLProtocol.handler = nil
            defaults.removePersistentDomain(forName: name)
        }
        let tokens = InMemoryTokenStore()
        let store = makeStore(defaults: defaults, tokens: tokens)

        try await signIn(store)

        #expect(store.isSignedIn)
        #expect(store.display?.sessionPercent == 42)
        #expect(store.isRefreshing == false)
        #expect(store.lastError == nil)
        #expect(tokens.count == 1)
    }

    @Test func signOutClearsSessionAndToken() async throws {
        let name = "LimitPeekTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            StubURLProtocol.handler = nil
            defaults.removePersistentDomain(forName: name)
        }
        let tokens = InMemoryTokenStore()
        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)

        store.signOut()

        #expect(!store.isSignedIn)
        #expect(store.display == nil)
        #expect(store.lastError == nil)
        #expect(store.rateLimit == nil)
        #expect(tokens.count == 0)
    }

    @Test func rateLimitBlocksRefreshUntilTheDeadline() async throws {
        let name = "LimitPeekTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            StubURLProtocol.handler = nil
            defaults.removePersistentDomain(forName: name)
        }
        let tokens = InMemoryTokenStore()
        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)

        StubURLProtocol.handler = { request in
            guard request.url?.path == "/api/oauth/usage" else { throw URLError(.unsupportedURL) }
            return try makeStubResponse(for: request,
                                        status: 429,
                                        body: #"{"error":"rate limited"}"#,
                                        headers: ["Retry-After": "120"])
        }

        let outcome = await store.refresh(force: true)
        #expect(outcome == .rateLimited(120))
        #expect(store.rateLimit != nil)
        #expect(store.lastError != nil)

        let blocked = await store.refresh(force: true)
        #expect(blocked == .skipped)
    }

    @Test func normalizesStaleAccountSelection() {
        let account = Account(id: "a", displayName: "A", organizationName: nil)

        #expect(AccountStore.normalizedSelection(nil, accounts: [account]) == "a")
        #expect(AccountStore.normalizedSelection("stale", accounts: [account]) == "a")
        #expect(AccountStore.normalizedSelection("a", accounts: [account]) == "a")
        #expect(AccountStore.normalizedSelection("a", accounts: []) == nil)
    }

    private func makeStore(defaults: UserDefaults, tokens: InMemoryTokenStore) -> AccountStore {
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                try makeStubResponse(for: request, body: tokenResponse)
            case "/api/oauth/profile":
                try makeStubResponse(for: request, body: profileResponse)
            case "/api/oauth/usage":
                try makeStubResponse(for: request, body: usageResponse)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let session = makeStubSession()
        return AccountStore(usageClient: UsageClient(session: session),
                            oauth: OAuthService(session: session),
                            tokenStore: tokens,
                            defaults: defaults)
    }

    private func signIn(_ store: AccountStore) async throws {
        let url = store.beginSignIn()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let state = try #require(components.queryItems?.first { $0.name == "state" }?.value)
        await store.completeSignIn(pastedCode: "code#\(state)")
    }
}

private let tokenResponse = """
{"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"user:profile"}
"""

private let profileResponse = """
{"account":{"uuid":"account-1","email":"alex@example.com","display_name":"Alex"},
 "organization":{"name":"Acme"}}
"""

private let usageResponse = """
{"limits":[{"kind":"session","percent":42,"resets_at":null}],
 "five_hour":{"utilization":42}}
"""
