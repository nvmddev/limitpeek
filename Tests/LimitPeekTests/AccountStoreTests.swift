import Foundation
import Testing
@testable import LimitPeek

@MainActor
@Suite(.serialized)
struct AccountStoreTests {
    @Test func completingSignInFetchesUsage() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let tokens = InMemoryTokenStore()
        let store = makeStore(defaults: defaults, tokens: tokens)

        #expect(try await signIn(store))

        #expect(store.isSignedIn)
        #expect(store.display?.sessionPercent == 42)
        #expect(store.isRefreshing == false)
        #expect(store.lastError == nil)
        #expect(tokens.count == 1)
    }

    @Test func aCodeFromAnotherSignInFails() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let store = makeStore(defaults: defaults, tokens: InMemoryTokenStore())

        _ = store.beginSignIn()

        #expect(await store.completeSignIn(pastedCode: "code#another-state") == false)
        #expect(!store.isSignedIn)
        #expect(store.lastError == OAuthError.stateMismatch.localizedDescription)
    }

    @Test func signOutClearsSessionAndToken() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let tokens = InMemoryTokenStore()
        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)

        store.signOut()

        #expect(!store.isSignedIn)
        #expect(store.display == nil)
        #expect(store.lastError == nil)
        #expect(store.rateLimitedUntil == nil)
        #expect(!store.canRefresh())
        #expect(tokens.count == 0)
    }

    @Test func rateLimitBlocksRefreshUntilTheDeadline() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let store = makeStore(defaults: defaults, tokens: InMemoryTokenStore())
        try await signIn(store)

        StubURLProtocol.handler = { request in
            guard request.url?.path == "/api/oauth/usage" else { throw URLError(.unsupportedURL) }
            return try makeStubResponse(for: request,
                                        status: 429,
                                        body: #"{"error":"rate limited"}"#,
                                        headers: ["Retry-After": "120"])
        }

        #expect(await store.refresh(force: true) == .rateLimited)
        // Retry-After is shorter than the floor, so the floor wins.
        let deadline = try #require(store.rateLimitedUntil)
        #expect(deadline.timeIntervalSinceNow > AccountStore.rateLimitFallback - 10)
        // The reading from the sign-in is fresh, so the countdown alone reports the 429.
        #expect(store.lastError == nil)
        #expect(store.display != nil)
        #expect(!store.canRefresh(at: deadline.addingTimeInterval(-1)))
        #expect(store.canRefresh(at: deadline))

        #expect(await store.refresh(force: true) == .skipped)
    }

    @Test func manualRefreshWaitsOutTheThrottle() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let store = makeStore(defaults: defaults, tokens: InMemoryTokenStore())
        try await signIn(store)

        #expect(!store.canRefresh())
        #expect(store.canRefresh(at: .now.addingTimeInterval(AccountStore.minRefreshInterval)))
        #expect(await store.refresh() == .skipped)
    }

    @Test func signingInAsSomeoneElseRemovesTheEarlierToken() async throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let tokens = InMemoryTokenStore()
        let profiles = LockedCounter()
        let store = makeStore(defaults: defaults, tokens: tokens, profileID: {
            profiles.increment() == 1 ? "account-1" : "account-2"
        })

        try await signIn(store)
        try await signIn(store)

        #expect(store.account?.id == "account-2")
        #expect(try tokens.load(for: "account-1") == nil)
        #expect(try tokens.load(for: "account-2") != nil)
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == nil)
    }

    @Test func keepsTheSelectedAccountFromAnEarlierList() throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let first = Account(id: "a", displayName: "A")
        let second = Account(id: "b", displayName: "B")
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "accounts")
        defaults.set("b", forKey: "selectedAccountID")

        let store = makeStore(defaults: defaults, tokens: InMemoryTokenStore())

        #expect(store.account == second)
        // The other account's token goes the way a sign-out would take it.
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == ["a"])
        #expect(defaults.string(forKey: "selectedAccountID") == nil)
        let saved = try JSONDecoder().decode([Account].self, from: try #require(defaults.data(forKey: "accounts")))
        #expect(saved == [second])
    }

    @Test func fallsBackToTheFirstStoredAccount() throws {
        let (name, defaults) = try makeDefaults()
        defer { tearDown(name, defaults) }
        let account = Account(id: "a", displayName: "A")
        defaults.set(try JSONEncoder().encode([account]), forKey: "accounts")
        defaults.set("stale", forKey: "selectedAccountID")

        let store = makeStore(defaults: defaults, tokens: InMemoryTokenStore())

        #expect(store.account == account)
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == nil)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "LimitPeekTests.\(UUID().uuidString)"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    private func tearDown(_ name: String, _ defaults: UserDefaults) {
        StubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: name)
    }

    private func makeStore(defaults: UserDefaults,
                           tokens: InMemoryTokenStore,
                           usageRequests: LockedCounter = LockedCounter(),
                           profileID: @escaping @Sendable () -> String = { "account-1" }) -> AccountStore {
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                return try makeStubResponse(for: request, body: tokenResponse)
            case "/api/oauth/profile":
                return try makeStubResponse(for: request, body: profileResponse(id: profileID()))
            case "/api/oauth/usage":
                usageRequests.increment()
                return try makeStubResponse(for: request, body: usageResponse)
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

    @discardableResult
    private func signIn(_ store: AccountStore) async throws -> Bool {
        let url = store.beginSignIn()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let state = try #require(components.queryItems?.first { $0.name == "state" }?.value)
        return await store.completeSignIn(pastedCode: "code#\(state)")
    }
}

private let tokenResponse = """
{"access_token":"access","refresh_token":"refresh","expires_in":3600,"scope":"user:profile"}
"""

private func profileResponse(id: String) -> String {
    """
    {"account":{"uuid":"\(id)","email":"alex@example.com","display_name":"Alex"},
     "organization":{"name":"Acme"}}
    """
}

private let usageResponse = """
{"limits":[{"kind":"session","percent":42,"resets_at":null}],
 "five_hour":{"utilization":42}}
"""
