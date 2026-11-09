import Foundation
import Observation

/// Owns the account, its token and the current reading.
@MainActor
@Observable
final class AccountStore {
    private(set) var account: Account?
    private(set) var display: UsageDisplay?
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var lastError: String?
    /// Set by a 429; every refresh path waits for it.
    private(set) var rateLimitedUntil: Date?
    /// A token the server rejected. Only a fresh sign-in or sign-out clears it;
    /// while it is set, a refresh never reaches the success path.
    private(set) var authIssue: AuthIssue?
    /// Shown when a sign-out could not remove the Keychain item.
    private(set) var tokenCleanupNotice: String?
    /// When the last request started, failed ones included.
    private(set) var lastRefreshAt = Date.distantPast

    /// Called after every change the polling loop cares about.
    @ObservationIgnored var onSessionStateChange: (@MainActor (SessionState) -> Void)?

    enum SessionState: Equatable, Sendable {
        case signedOut
        case signedIn
        case reauthenticationRequired
    }

    /// A persistent problem that a fresh sign-in attempt may fix; a server-side
    /// plan or organization block can outlast it.
    enum AuthIssue: Equatable, Sendable {
        case sessionExpired
        case missingToken
        case forbidden
    }

    enum RefreshOutcome: Equatable, Sendable {
        case updated
        case rateLimited
        case failed
        case skipped
        case signedOut
        case requiresReauthentication
    }

    /// Floor between usage requests: at most three per minute, except the
    /// first fetch after sign-in.
    nonisolated static let minRefreshInterval: TimeInterval = 20
    /// Floor for the shared 429 deadline; Retry-After wins only when longer.
    nonisolated static let rateLimitFallback: TimeInterval = 300
    /// Opening the menu fetches a reading older than this.
    nonisolated static let staleAfter: TimeInterval = 60

    /// The challenge for the sign-in waiting on a pasted code.
    private var pendingPKCE: PKCE?
    /// Read from the Keychain once per launch. macOS authorises reads
    /// individually, so hitting it on every poll meant a prompt on every poll.
    private var cachedToken: TokenPair?
    /// Bumped on sign-in and sign-out so an older request cannot write state.
    private var sessionGeneration = 0
    private var pendingTokenCleanup: [String] = []

    private let usageClient: UsageClient
    private let oauth: OAuthService
    private let tokenStore: any TokenStoring
    private let defaults: UserDefaults

    private enum Keys {
        static let accounts = "accounts"
        static let selectedAccountID = "selectedAccountID"
        static let pendingTokenCleanup = "pendingTokenCleanup"
    }

    private static let tokenCleanupNoticeText =
        "Signed out, but the saved Keychain token could not be removed. LimitPeek will retry."

    var isSignedIn: Bool { account != nil }

    var needsReauthentication: Bool { authIssue != nil }

    var sessionState: SessionState {
        guard account != nil else { return .signedOut }
        return authIssue == nil ? .signedIn : .reauthenticationRequired
    }

    /// Whether a manual refresh would send a request right now.
    func canRefresh(at now: Date = .now) -> Bool {
        account != nil && authIssue == nil && !isRefreshing
            && now >= rateLimitedUntil ?? .distantPast
            && now.timeIntervalSince(lastRefreshAt) >= Self.minRefreshInterval
    }

    init(usageClient: UsageClient = UsageClient(),
         oauth: OAuthService = OAuthService(),
         tokenStore: any TokenStoring = TokenStore(),
         defaults: UserDefaults = .standard) {
        self.usageClient = usageClient
        self.oauth = oauth
        self.tokenStore = tokenStore
        self.defaults = defaults
        pendingTokenCleanup = defaults.stringArray(forKey: Keys.pendingTokenCleanup) ?? []
        loadAccount()
        tokenCleanupNotice = pendingTokenCleanup.isEmpty ? nil : Self.tokenCleanupNoticeText
    }

    #if DEBUG
    /// For `scripts/ReadmeArt.swift`.
    init(fixture account: Account, display: UsageDisplay) {
        usageClient = UsageClient()
        oauth = OAuthService()
        tokenStore = TokenStore()
        defaults = .standard
        self.account = account
        self.display = display
    }
    #endif

    // MARK: - Sign in

    func beginSignIn() -> URL {
        lastError = nil
        let pkce = PKCE()
        pendingPKCE = pkce
        return oauth.authorizationURL(pkce: pkce)
    }

    func cancelSignIn() {
        pendingPKCE = nil
    }

    /// True once the account is signed in and its first reading requested.
    @discardableResult
    func completeSignIn(pastedCode: String) async -> Bool {
        guard !isSigningIn else { return false }
        guard let pkce = pendingPKCE else {
            lastError = "Start the sign-in again."
            return false
        }
        isSigningIn = true
        lastError = nil

        do {
            let pair = try await oauth.exchange(pastedCode: pastedCode, pkce: pkce)
            // The code is spent; a failure below needs a fresh sign-in.
            pendingPKCE = nil
            let signedIn = try await usageClient.fetchProfile(accessToken: pair.accessToken,
                                                              scopes: pair.scopes)
            try tokenStore.save(pair, for: signedIn.id)
            // A fresh token replaces any item an earlier sign-out left behind.
            forgetPendingTokenCleanup(signedIn.id)

            // Signing in as someone else replaces the account, and its token
            // goes the way a sign-out would take it.
            let replaced = account.flatMap { $0.id == signedIn.id ? nil : $0 }
            if let replaced { rememberPendingTokenCleanup(replaced.id) }
            beginSession(signedIn, token: pair)
            if let replaced { deleteToken(for: replaced.id) }

            isSigningIn = false
            await refresh(force: true)
            notifySessionStateChange()
            return true
        } catch {
            isSigningIn = false
            lastError = error.localizedDescription
            notifySessionStateChange()
            return false
        }
    }

    // MARK: - Sign out

    func signOut() {
        guard let account else { return }
        removeAccount(account, error: nil)
    }

    /// Best-effort Keychain cleanup left over from a failed sign-out delete.
    func retryPendingTokenCleanup() {
        for accountID in pendingTokenCleanup {
            if accountID == account?.id {
                // The signed-in account still owns the item. Once its token
                // is in use the entry is stale; before that, keep it.
                if cachedToken != nil { forgetPendingTokenCleanup(accountID) }
                continue
            }
            do {
                try tokenStore.delete(for: accountID)
                forgetPendingTokenCleanup(accountID)
            } catch {
                // Still pending; the next retry tries again.
            }
        }
        if pendingTokenCleanup.isEmpty { tokenCleanupNotice = nil }
    }

    // MARK: - Refresh

    @discardableResult
    func refresh(force: Bool = false) async -> RefreshOutcome {
        guard let account else { return .signedOut }
        // A rejected token is not worth another request.
        guard authIssue == nil else { return .requiresReauthentication }
        guard !isRefreshing else { return .skipped }
        if let rateLimitedUntil {
            guard Date.now >= rateLimitedUntil else { return .skipped }
            self.rateLimitedUntil = nil
        }
        guard force || Date.now.timeIntervalSince(lastRefreshAt) >= Self.minRefreshInterval else {
            return .skipped
        }
        let generation = sessionGeneration
        isRefreshing = true
        // Count failed attempts too: an error must not be hammered either.
        lastRefreshAt = .now
        defer {
            // A new session has already reset it, and may be refreshing itself.
            if isCurrent(generation) { isRefreshing = false }
        }

        do {
            let response = try await withValidToken(for: account, generation: generation) { token, scopes in
                try await usageClient.fetchUsage(accessToken: token, scopes: scopes)
            }
            guard isCurrent(generation) else { return .skipped }
            display = UsageDisplay(response)
            lastError = nil
            return .updated
        } catch {
            guard isCurrent(generation) else { return .skipped }
            return recordFailure(error)
        }
    }

    /// Fetches only when the reading on screen is older than `staleAfter`.
    func refreshIfStale() async {
        if let fetchedAt = display?.fetchedAt,
           Date.now.timeIntervalSince(fetchedAt) <= Self.staleAfter { return }
        await refresh()
    }

    private func recordFailure(_ error: any Error) -> RefreshOutcome {
        switch error {
        case APIError.rateLimited(let retryAfter):
            rateLimitedUntil = .now.addingTimeInterval(max(retryAfter ?? 0, Self.rateLimitFallback))
            lastError = error.localizedDescription
            return .rateLimited
        case APIError.unauthorized:
            // The rotation retry has already run; the token is really rejected.
            return requireReauthentication(.sessionExpired, error)
        case APIError.noStoredToken:
            return requireReauthentication(.missingToken, error)
        case APIError.forbidden:
            // A valid token the server refuses: a fresh sign-in can fix stale
            // scopes, but not a plan-level block.
            return requireReauthentication(.forbidden, error)
        case is CancellationError, URLError.cancelled:
            // Sleep, sign-out and wake cancel the waiting request; that is not
            // an error to show or to keep in state.
            return .skipped
        default:
            if Task.isCancelled { return .skipped }
            lastError = error.localizedDescription
            return .failed
        }
    }

    private func requireReauthentication(_ issue: AuthIssue, _ error: any Error) -> RefreshOutcome {
        lastError = error.localizedDescription
        if authIssue != issue {
            authIssue = issue
            notifySessionStateChange()
        }
        return .requiresReauthentication
    }

    /// Refreshes before expiry, and once more if the server rejects the token
    /// anyway (clock skew, early revocation).
    private func withValidToken<T: Sendable>(for account: Account,
                                             generation: Int,
                                             _ body: (String, [String]) async throws -> T) async throws -> T {
        guard var pair = try token(for: account) else { throw APIError.noStoredToken }
        if pair.needsRefresh() {
            pair = try await rotate(pair, for: account, generation: generation)
        }
        do {
            return try await body(pair.accessToken, pair.scopes)
        } catch APIError.unauthorized {
            // Only a 401 is worth retrying: a 403 means the scopes are wrong,
            // and a fresh token carries the same ones.
            let rotated = try await rotate(pair, for: account, generation: generation)
            return try await body(rotated.accessToken, rotated.scopes)
        }
    }

    private func token(for account: Account) throws -> TokenPair? {
        if cachedToken == nil {
            cachedToken = try tokenStore.load(for: account.id)
        }
        return cachedToken
    }

    /// Writes the new pair before dropping the old one, so a crash mid-rotation
    /// leaves a usable token.
    private func rotate(_ pair: TokenPair, for account: Account, generation: Int) async throws -> TokenPair {
        do {
            let refreshed = try await oauth.refresh(pair)
            guard isCurrent(generation), cachedToken?.refreshToken == pair.refreshToken else {
                throw CancellationError()
            }
            try tokenStore.save(refreshed, for: account.id)
            cachedToken = refreshed
            return refreshed
        } catch OAuthError.invalidGrant {
            if isCurrent(generation), cachedToken?.refreshToken == pair.refreshToken {
                removeAccount(account, error: OAuthError.invalidGrant.localizedDescription)
            }
            throw OAuthError.invalidGrant
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        sessionGeneration == generation
    }

    // MARK: - Session

    private func beginSession(_ account: Account, token: TokenPair) {
        if self.account?.id != account.id { display = nil }
        sessionGeneration += 1
        self.account = account
        cachedToken = token
        isRefreshing = false
        rateLimitedUntil = nil
        authIssue = nil
        lastRefreshAt = .distantPast
        saveAccount()
    }

    /// Persists the cleanup ID before the record goes and deletes the token
    /// last, so every crash window leaves either the account or a pending
    /// entry that `retryPendingTokenCleanup` can finish.
    private func removeAccount(_ account: Account, error: String?) {
        rememberPendingTokenCleanup(account.id)
        sessionGeneration += 1
        self.account = nil
        cachedToken = nil
        display = nil
        isRefreshing = false
        rateLimitedUntil = nil
        authIssue = nil
        pendingPKCE = nil
        lastRefreshAt = .distantPast
        lastError = error
        saveAccount()
        notifySessionStateChange()
        deleteToken(for: account.id)
    }

    private func deleteToken(for accountID: String) {
        do {
            try tokenStore.delete(for: accountID)
            forgetPendingTokenCleanup(accountID)
        } catch {
            // Keep the pending ID; the next retry removes the orphaned token.
            tokenCleanupNotice = Self.tokenCleanupNoticeText
        }
    }

    private func notifySessionStateChange() {
        onSessionStateChange?(sessionState)
    }

    // MARK: - Pending Keychain cleanup

    private func rememberPendingTokenCleanup(_ accountID: String) {
        guard !pendingTokenCleanup.contains(accountID) else { return }
        pendingTokenCleanup.append(accountID)
        defaults.set(pendingTokenCleanup, forKey: Keys.pendingTokenCleanup)
    }

    private func forgetPendingTokenCleanup(_ accountID: String) {
        guard let index = pendingTokenCleanup.firstIndex(of: accountID) else { return }
        pendingTokenCleanup.remove(at: index)
        if pendingTokenCleanup.isEmpty {
            defaults.removeObject(forKey: Keys.pendingTokenCleanup)
            tokenCleanupNotice = nil
        } else {
            defaults.set(pendingTokenCleanup, forKey: Keys.pendingTokenCleanup)
        }
    }

    // MARK: - Persistence (metadata only, never tokens)

    /// Stored as a list, the format earlier builds wrote. They could keep a
    /// second account after a sign-in as someone else; the selected one stays
    /// and the others' tokens go.
    private func loadAccount() {
        guard let data = defaults.data(forKey: Keys.accounts),
              let stored = try? JSONDecoder().decode([Account].self, from: data) else { return }
        let selectedID = defaults.string(forKey: Keys.selectedAccountID)
        account = stored.first { $0.id == selectedID } ?? stored.first
        let others = stored.filter { $0.id != account?.id }
        guard !others.isEmpty || selectedID != nil else { return }
        others.forEach { rememberPendingTokenCleanup($0.id) }
        saveAccount()
    }

    private func saveAccount() {
        defaults.set(try? JSONEncoder().encode(account.map { [$0] } ?? []), forKey: Keys.accounts)
        defaults.removeObject(forKey: Keys.selectedAccountID)
    }
}
