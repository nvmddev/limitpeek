import Foundation
import Testing
@testable import LimitPeek

@MainActor
@Suite(.serialized)
struct AccountStoreRaceTests {
    // MARK: - A stale response must not overwrite a newer session

    @Test func staleResponseAfterSignOutAndSignInLeavesNewSessionAlone() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let gate = AsyncGate()
        defer { gate.release() }
        let tokenCalls = LockedCounter()
        let usageCalls = LockedCounter()

        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                let call = tokenCalls.increment()
                return try raceResponse(for: request,
                                        body: raceTokenBody(access: call == 1 ? "access-old" : "access-new"))
            case "/api/oauth/profile":
                return try raceResponse(for: request, body: raceProfileBody)
            case "/api/oauth/usage":
                let call = usageCalls.increment()
                if call == 2 {
                    return try raceResponse(for: request, body: raceUsageBody(percent: 99))
                }
                return try raceResponse(for: request,
                                        body: raceUsageBody(percent: call == 1 ? 42 : 77))
            default:
                throw URLError(.unsupportedURL)
            }
        }
        RaceURLProtocol.gateProvider = { request in
            request.url?.path == "/api/oauth/usage" && usageCalls.current == 2 ? gate : nil
        }
        defer {
            RaceURLProtocol.handler = nil
            RaceURLProtocol.gateProvider = nil
        }

        let store = makeStore(defaults: defaults, tokens: tokens)
        var states: [AccountStore.SessionState] = []
        store.onSessionStateChange = { states.append($0) }

        try await signIn(store)
        #expect(store.display?.sessionPercent == 42)

        let oldRefresh = Task { await store.refresh(force: true) }
        try await withTimeout(seconds: 10) { await gate.waitForArrival() }
        #expect(usageCalls.current == 2)

        store.signOut()
        #expect(!store.isSignedIn)
        #expect(tokens.pair(for: raceAccountID) == nil)

        try await signIn(store)
        #expect(store.display?.sessionPercent == 77)
        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-new")

        gate.release()
        let oldOutcome = try await withTimeout(seconds: 10) { await oldRefresh.value }
        #expect(oldOutcome == .skipped)

        #expect(store.isSignedIn)
        #expect(store.selectedAccount?.id == raceAccountID)
        #expect(store.display?.sessionPercent == 77)
        #expect(store.lastError == nil)
        #expect(store.rateLimit == nil)
        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-new")
        #expect(states.contains(.signedOut))
        #expect(states.last == .signedIn)
    }

    // MARK: - Persistent authentication failures

    @Test func unauthorizedAfterRotationKeepsAccountAndDisplay() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let tokenCalls = LockedCounter()
        let usageCalls = LockedCounter()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 60)

        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                let call = tokenCalls.increment()
                return try raceResponse(for: request,
                                        body: raceTokenBody(access: "rotated-\(call)", expiresIn: 3600))
            case "/api/oauth/usage":
                let call = usageCalls.increment()
                if call == 1 {
                    return try raceResponse(for: request, body: raceUsageBody(percent: 42))
                }
                return try raceResponse(for: request, status: 401, body: #"{"error":"unauthorized"}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        var states: [AccountStore.SessionState] = []
        store.onSessionStateChange = { states.append($0) }

        #expect(await store.refresh(force: true) == .updated)
        #expect(store.display?.sessionPercent == 42)

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        #expect(store.authIssue == .sessionExpired)
        #expect(store.needsReauthentication)
        #expect(store.sessionState == .reauthenticationRequired)
        #expect(store.isSignedIn)
        #expect(store.display?.sessionPercent == 42)
        #expect(store.lastError == APIError.unauthorized.localizedDescription)
        #expect(tokens.pair(for: raceAccountID) != nil)
        #expect(states.contains(.reauthenticationRequired))
    }

    @Test func missingTokenAsksForReauthenticationWithoutARequest() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let account = Account(id: raceAccountID, displayName: "Alex", organizationName: nil)
        defaults.set(try JSONEncoder().encode([account]), forKey: "accounts")
        defaults.set(account.id, forKey: "selectedAccountID")
        let usageCalls = LockedCounter()

        RaceURLProtocol.handler = { request in
            _ = usageCalls.increment()
            return try raceResponse(for: request, body: raceUsageBody(percent: 42))
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        #expect(store.authIssue == .missingToken)
        #expect(store.isSignedIn)
        #expect(usageCalls.current == 0)
    }

    @Test func refreshDoesNotHitTheNetworkWhileReauthenticationIsRequired() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let tokenCalls = LockedCounter()
        let usageCalls = LockedCounter()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 3600)

        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                let call = tokenCalls.increment()
                return try raceResponse(for: request,
                                        body: raceTokenBody(access: "rotated-\(call)", expiresIn: 3600))
            case "/api/oauth/usage":
                _ = usageCalls.increment()
                return try raceResponse(for: request, status: 401, body: #"{"error":"unauthorized"}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        let requestsWhenRejected = usageCalls.current
        #expect(requestsWhenRejected == 2)

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        #expect(usageCalls.current == requestsWhenRejected)
        #expect(store.isSignedIn)
    }

    // MARK: - Sign-out survives a failing Keychain delete

    @Test func signOutKeepsGoingWhenKeychainDeleteFails() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                return try raceResponse(for: request, body: raceTokenBody(access: "access"))
            case "/api/oauth/profile":
                return try raceResponse(for: request, body: raceProfileBody)
            case "/api/oauth/usage":
                return try raceResponse(for: request, body: raceUsageBody(percent: 42))
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)
        let accountID = try #require(store.selectedAccount?.id)

        tokens.failDeletes()
        store.signOut()

        #expect(!store.isSignedIn)
        #expect(store.display == nil)
        #expect(store.lastError == nil)
        #expect(store.rateLimit == nil)
        #expect(store.authIssue == nil)
        #expect(store.sessionState == .signedOut)
        #expect(store.tokenCleanupNotice != nil)
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == [accountID])
        #expect(tokens.pair(for: accountID) != nil)
    }

    @Test func retryPendingTokenCleanupRemovesTheStaleToken() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                return try raceResponse(for: request, body: raceTokenBody(access: "access"))
            case "/api/oauth/profile":
                return try raceResponse(for: request, body: raceProfileBody)
            case "/api/oauth/usage":
                return try raceResponse(for: request, body: raceUsageBody(percent: 42))
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)
        let accountID = try #require(store.selectedAccount?.id)

        tokens.failDeletes()
        store.signOut()
        #expect(tokens.pair(for: accountID) != nil)

        tokens.allowDeletes()
        store.retryPendingTokenCleanup()

        #expect(tokens.pair(for: accountID) == nil)
        #expect(store.tokenCleanupNotice == nil)
        #expect((defaults.stringArray(forKey: "pendingTokenCleanup") ?? []).isEmpty)
    }

    @Test func retryKeepsATokenCachedForTheAccount() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        try seedSignedIn(defaults: defaults, tokens: tokens,
                         expiresIn: 3600, pendingCleanup: true)

        RaceURLProtocol.handler = { request in
            guard request.url?.path == "/api/oauth/usage" else { throw URLError(.unsupportedURL) }
            return try raceResponse(for: request, body: raceUsageBody(percent: 42))
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        #expect(store.tokenCleanupNotice != nil)

        #expect(await store.refresh(force: true) == .updated)
        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-old")

        store.retryPendingTokenCleanup()

        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-old")
        #expect(store.tokenCleanupNotice == nil)
        #expect((defaults.stringArray(forKey: "pendingTokenCleanup") ?? []).isEmpty)
    }

    @Test func retryAfterANewSignInKeepsTheNewToken() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let tokenCalls = LockedCounter()
        RaceURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                let call = tokenCalls.increment()
                return try raceResponse(for: request,
                                        body: raceTokenBody(access: call == 1 ? "access-old" : "access-new"))
            case "/api/oauth/profile":
                return try raceResponse(for: request, body: raceProfileBody)
            case "/api/oauth/usage":
                return try raceResponse(for: request, body: raceUsageBody(percent: 42))
            default:
                throw URLError(.unsupportedURL)
            }
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        try await signIn(store)

        tokens.failDeletes()
        store.signOut()
        #expect(store.tokenCleanupNotice != nil)

        tokens.allowDeletes()
        try await signIn(store)
        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-new")

        store.retryPendingTokenCleanup()

        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-new")
        #expect(store.tokenCleanupNotice == nil)
    }

    @Test func retryKeepsPendingForAnActiveAccountBeforeAnyRefresh() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        try seedSignedIn(defaults: defaults, tokens: tokens,
                         expiresIn: 3600, pendingCleanup: true)

        let store = makeStore(defaults: defaults, tokens: tokens)
        #expect(store.isSignedIn)
        #expect(store.tokenCleanupNotice != nil)
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == [raceAccountID])

        store.retryPendingTokenCleanup()

        #expect(tokens.pair(for: raceAccountID)?.accessToken == "access-old")
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == [raceAccountID])
        #expect(store.tokenCleanupNotice != nil)
    }

    @Test func rateLimitWithoutRetryAfterBlocksAManualRefresh() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 3600)

        RaceURLProtocol.handler = { request in
            guard request.url?.path == "/api/oauth/usage" else { throw URLError(.unsupportedURL) }
            return try raceResponse(for: request,
                                    status: 429,
                                    body: #"{"error":"rate limited"}"#)
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        #expect(await store.refresh(force: true) == .rateLimited(nil))

        let deadline = try #require(store.rateLimit?.deadline)
        #expect(deadline.timeIntervalSinceNow >= 299)

        var schedule = PollSchedule()
        #expect(schedule.nextDelay(after: .rateLimited(nil), isLowPowerMode: false)
                == AccountStore.rateLimitFallback)
        #expect(await store.refresh(force: true) == .skipped)
    }

    @Test func invalidGrantRemembersTheTokenWhenDeleteFails() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 60)
        tokens.failDeletes()

        RaceURLProtocol.handler = { request in
            guard request.url?.path == "/v1/oauth/token" else { throw URLError(.unsupportedURL) }
            return try raceResponse(for: request,
                                    status: 400,
                                    body: #"{"error":"invalid_grant"}"#)
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        #expect(await store.refresh(force: true) == .skipped)

        #expect(!store.isSignedIn)
        #expect(store.authIssue == nil)
        #expect(store.lastError == OAuthError.invalidGrant.localizedDescription)
        #expect(store.tokenCleanupNotice != nil)
        #expect(defaults.stringArray(forKey: "pendingTokenCleanup") == [raceAccountID])
        #expect(tokens.pair(for: raceAccountID) != nil)
    }

    @Test func forbiddenUsageAsksForReauthenticationWithoutDeletingTheAccount() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        let usageCalls = LockedCounter()
        let rejectUsage = LockedFlag()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 3600)

        RaceURLProtocol.handler = { request in
            guard request.url?.path == "/api/oauth/usage" else { throw URLError(.unsupportedURL) }
            guard rejectUsage.isSet else {
                return try raceResponse(for: request, body: raceUsageBody(percent: 42))
            }
            _ = usageCalls.increment()
            return try raceResponse(for: request, status: 403, body: #"{"error":"forbidden"}"#)
        }
        defer { RaceURLProtocol.handler = nil }

        let store = makeStore(defaults: defaults, tokens: tokens)
        #expect(await store.refresh(force: true) == .updated)
        #expect(store.display?.sessionPercent == 42)

        rejectUsage.set()

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        #expect(store.authIssue == .forbidden)
        #expect(store.needsReauthentication)
        #expect(store.sessionState == .reauthenticationRequired)
        #expect(store.isSignedIn)
        #expect(store.display?.sessionPercent == 42)
        #expect(store.lastError
                == APIError.forbidden(scopes: ["user:profile"]).localizedDescription)
        #expect(tokens.pair(for: raceAccountID) != nil)
        #expect(usageCalls.current == 1)

        #expect(await store.refresh(force: true) == .requiresReauthentication)
        #expect(usageCalls.current == 1)
        #expect(store.isSignedIn)
    }

    // MARK: - Sign-out ordering

    @Test func signOutPersistsCleanupBeforeDeletingTheToken() throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        let tokens = RaceTokenStore()
        try seedSignedIn(defaults: defaults, tokens: tokens, expiresIn: 3600)
        let store = makeStore(defaults: defaults, tokens: tokens)

        let probe = OrderProbe()
        tokens.onDelete = {
            MainActor.assumeIsolated {
                probe.record(accountPresent: store.isSignedIn)
            }
        }

        store.signOut()

        #expect(probe.accountWasPresent == false)
        #expect(!store.isSignedIn)
        #expect(store.accounts.isEmpty)
        #expect(tokens.pair(for: raceAccountID) == nil)
        #expect((defaults.stringArray(forKey: "pendingTokenCleanup") ?? []).isEmpty)
        #expect(store.tokenCleanupNotice == nil)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "LimitPeekTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (name, defaults)
    }

    private func makeStore(defaults: UserDefaults, tokens: RaceTokenStore) -> AccountStore {
        let session = RaceURLProtocol.makeSession()
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

    private func seedSignedIn(defaults: UserDefaults,
                              tokens: RaceTokenStore,
                              expiresIn: TimeInterval,
                              pendingCleanup: Bool = false) throws {
        let account = Account(id: raceAccountID, displayName: "Alex", organizationName: "Acme")
        defaults.set(try JSONEncoder().encode([account]), forKey: "accounts")
        defaults.set(account.id, forKey: "selectedAccountID")
        try tokens.save(TokenPair(accessToken: "access-old",
                                  refreshToken: "refresh-old",
                                  expiresAt: Date().addingTimeInterval(expiresIn),
                                  scopes: ["user:profile"]),
                        for: account.id)
        if pendingCleanup {
            defaults.set([account.id], forKey: "pendingTokenCleanup")
        }
    }
}

// MARK: - Bounded waits

private struct TimeoutExpired: Error {}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ result: Result<T, Error>,
                _ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

/// Races an operation against a wall-clock deadline so a broken test cannot
/// hang the suite. The loser stays suspended only until its work is released.
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T
) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withCheckedThrowingContinuation { continuation in
        Task {
            let value = await operation()
            race.finish(.success(value), continuation)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            race.finish(.failure(TimeoutExpired()), continuation)
        }
    }
}

// MARK: - Test doubles local to this suite

/// Only used by this file, so it cannot race the shared `StubURLProtocol`.
private final class RaceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Returns a gate when the computed response should be held back.
    nonisolated(unsafe) static var gateProvider: (@Sendable (URLRequest) -> AsyncGate?)?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RaceURLProtocol.self]
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            if let gate = Self.gateProvider?(request) {
                let delivery = DelayedDelivery(owner: self, response: response, data: data)
                Task {
                    await gate.arriveAndWaitForRelease()
                    delivery.send()
                }
            } else {
                deliver(response, data)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    fileprivate func deliver(_ response: HTTPURLResponse, _ data: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Carries an already-computed response across the delay without exposing the
/// non-Sendable URLProtocol machinery to the concurrency checker.
private final class DelayedDelivery: @unchecked Sendable {
    private let owner: RaceURLProtocol
    private let response: HTTPURLResponse
    private let data: Data

    init(owner: RaceURLProtocol, response: HTTPURLResponse, data: Data) {
        self.owner = owner
        self.response = response
        self.data = data
    }

    func send() {
        owner.deliver(response, data)
    }
}

/// Holds one response without blocking the URL loading thread: `arrive` wakes
/// the test, `release` lets the response through. Continuations are one-shot.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = false
    private var released = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arriveAndWaitForRelease() async {
        arrive()
        await waitForRelease()
    }

    func waitForArrival() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if arrived {
                lock.unlock()
                continuation.resume()
            } else {
                arrivalWaiter = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        released = true
        let waiter = releaseWaiter
        releaseWaiter = nil
        lock.unlock()
        waiter?.resume()
    }

    private func arrive() {
        lock.lock()
        arrived = true
        let waiter = arrivalWaiter
        arrivalWaiter = nil
        lock.unlock()
        waiter?.resume()
    }

    private func waitForRelease() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
            } else {
                releaseWaiter = continuation
                lock.unlock()
            }
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Records whether the account still existed when its token was deleted.
private final class OrderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var present = true

    func record(accountPresent: Bool) {
        lock.lock()
        defer { lock.unlock() }
        present = accountPresent
    }

    var accountWasPresent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return present
    }
}

private final class RaceTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var pairs: [String: TokenPair] = [:]
    private var deleteFailure: Error?
    /// Called synchronously at the start of `delete`, before the item is gone.
    var onDelete: (@Sendable () -> Void)?

    func save(_ pair: TokenPair, for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        pairs[accountID] = pair
    }

    func load(for accountID: String) throws -> TokenPair? {
        lock.lock()
        defer { lock.unlock() }
        return pairs[accountID]
    }

    func delete(for accountID: String) throws {
        onDelete?()
        lock.lock()
        defer { lock.unlock() }
        if let deleteFailure { throw deleteFailure }
        pairs[accountID] = nil
    }

    func pair(for accountID: String) -> TokenPair? {
        lock.lock()
        defer { lock.unlock() }
        return pairs[accountID]
    }

    func failDeletes() {
        lock.lock()
        defer { lock.unlock() }
        deleteFailure = KeychainError.status(-25300)
    }

    func allowDeletes() {
        lock.lock()
        defer { lock.unlock() }
        deleteFailure = nil
    }
}

private let raceAccountID = "account-1"

private let raceProfileBody = """
{"account":{"uuid":"account-1","email":"alex@example.com","display_name":"Alex"},
 "organization":{"name":"Acme"}}
"""

private func raceTokenBody(access: String,
                           refresh: String = "refresh",
                           expiresIn: Int = 3600) -> String {
    #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn),"scope":"user:profile"}"#
}

private func raceUsageBody(percent: Double) -> String {
    #"{"limits":[{"kind":"session","percent":\#(percent),"resets_at":null}],"five_hour":{"utilization":\#(percent)}}"#
}

private func raceResponse(for request: URLRequest,
                          status: Int = 200,
                          body: String) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url,
                                         statusCode: status,
                                         httpVersion: nil,
                                         headerFields: nil) else {
        throw URLError(.badURL)
    }
    return (response, Data(body.utf8))
}
