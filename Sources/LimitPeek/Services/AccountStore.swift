import Foundation
import Observation

/// Owns accounts, tokens and the current reading.
@MainActor
@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []
    var selectedAccountID: String?
    private(set) var display: UsageDisplay?
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    private(set) var lastError: String?
    /// Set by a 429; every refresh path honors its deadline.
    private(set) var rateLimit: RateLimit?
    /// A token the server rejected. Only a fresh sign-in or sign-out clears it;
    /// while it is set, a refresh never reaches the success path.
    private(set) var authIssue: AuthIssue?
    /// Shown when a sign-out could not remove the Keychain item.
    private(set) var tokenCleanupNotice: String?

    /// Called after every change the polling loop cares about.
    @ObservationIgnored var onSessionStateChange: (@MainActor (SessionState) -> Void)?

    struct RateLimit {
        var deadline: Date
    }

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

    enum RefreshOutcome: Sendable, Equatable {
        case updated
        case rateLimited(TimeInterval?)
        case failed
        case skipped
        case signedOut
        case requiresReauthentication
    }

    /// Holds the challenge for the sign-in waiting on a pasted code.
    private(set) var pendingPKCE: PKCE?

    /// Read from the Keychain once per launch. macOS authorises reads
    /// individually, so hitting it on every poll meant a prompt on every poll.
    private var tokenCache: [String: TokenPair] = [:]

    private let usageClient: UsageClient
    private let oauth: OAuthService
    private let tokenStore: any TokenStoring
    private let defaults: UserDefaults
    private let accountsKey = "accounts"
    private let pendingTokenCleanupKey = "pendingTokenCleanup"
    private var pendingTokenCleanup: [String] = []
    private static let tokenCleanupNoticeText =
        "Signed out, but the saved Keychain token could not be removed. LimitPeek will retry."

    /// Floor between usage requests: at most three per minute, except the
    /// first fetch after sign-in.
    static let minRefreshInterval: TimeInterval = 20
    /// Floor for the shared 429 deadline; Retry-After wins only when longer.
    nonisolated static let rateLimitFallback: TimeInterval = 300
    private var lastRefreshAt = Date.distantPast
    /// Bumped on sign-in and sign-out so an older request cannot write state.
    private var sessionGeneration = 0
    private var refreshCounter = 0
    /// The refresh allowed to clear `isRefreshing`.
    private var activeRefreshID: Int?

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    var isSignedIn: Bool { selectedAccount != nil }

    var needsReauthentication: Bool { authIssue != nil }

    var sessionState: SessionState {
        guard selectedAccount != nil else { return .signedOut }
        return authIssue == nil ? .signedIn : .reauthenticationRequired
    }

    init(usageClient: UsageClient = UsageClient(),
         oauth: OAuthService = OAuthService(),
         tokenStore: any TokenStoring = TokenStore(),
         defaults: UserDefaults = .standard) {
        self.usageClient = usageClient
        self.oauth = oauth
        self.tokenStore = tokenStore
        self.defaults = defaults
        loadAccounts()
        loadPendingTokenCleanup()
    }

    #if DEBUG
    /// For previews and `scripts/ReadmeArt.swift`.
    init(fixture account: Account, display: UsageDisplay) {
        usageClient = UsageClient()
        oauth = OAuthService()
        tokenStore = TokenStore()
        defaults = .standard
        accounts = [account]
        selectedAccountID = account.id
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

    func completeSignIn(pastedCode: String) async {
        guard !isSigningIn else { return }
        guard let pkce = pendingPKCE else {
            lastError = "Start the sign-in again."
            return
        }
        isSigningIn = true
        lastError = nil

        do {
            let pair = try await oauth.exchange(pastedCode: pastedCode, pkce: pkce)
            // The code is spent; a failure below needs a fresh sign-in.
            pendingPKCE = nil
            let account = try await usageClient.fetchProfile(accessToken: pair.accessToken,
                                                             scopes: pair.scopes)
            try tokenStore.save(pair, for: account.id)
            tokenCache[account.id] = pair
            // A fresh token replaces any item an earlier sign-out left behind.
            forgetPendingTokenCleanup(account.id)

            sessionGeneration += 1
            invalidateActiveRefresh()
            rateLimit = nil
            lastRefreshAt = .distantPast
            accounts.removeAll { $0.id == account.id }
            accounts.append(account)
            selectedAccountID = account.id
            saveAccounts()
            authIssue = nil

            isSigningIn = false
            await refresh(force: true)
            notifySessionStateChange()
        } catch {
            isSigningIn = false
            lastError = error.localizedDescription
            notifySessionStateChange()
        }
    }

    // MARK: - Sign out

    /// Always signs out. The cleanup ID is persisted before the metadata goes
    /// away, so every crash window leaves either the account or a pending entry
    /// that can safely remove the token later.
    func signOut() {
        guard let account = selectedAccount else { return }
        // Persist first: the ID must outlive both the metadata and the delete.
        rememberPendingTokenCleanup(account.id)

        tokenCache[account.id] = nil
        sessionGeneration += 1
        invalidateActiveRefresh()
        accounts.removeAll { $0.id == account.id }
        selectedAccountID = accounts.first?.id
        display = nil
        lastError = nil
        rateLimit = nil
        pendingPKCE = nil
        authIssue = nil
        lastRefreshAt = .distantPast
        saveAccounts()
        notifySessionStateChange()

        do {
            try tokenStore.delete(for: account.id)
            forgetPendingTokenCleanup(account.id)
        } catch {
            // Keep the pending ID; the next retry removes the orphaned token.
            tokenCleanupNotice = Self.tokenCleanupNoticeText
        }
    }

    /// Best-effort Keychain cleanup left over from a failed sign-out delete.
    /// A cached token means the account is active; never delete its token.
    func retryPendingTokenCleanup() {
        guard !pendingTokenCleanup.isEmpty else {
            tokenCleanupNotice = nil
            return
        }
        for accountID in pendingTokenCleanup {
            if tokenCache[accountID] != nil {
                // A cached pair can also come from a refresh of the old token;
                // either way the account is active, so keep its token.
                forgetPendingTokenCleanup(accountID)
                continue
            }
            // A live account may still own the item: keep the pending entry.
            guard !accounts.contains(where: { $0.id == accountID }) else { continue }
            do {
                try tokenStore.delete(for: accountID)
                forgetPendingTokenCleanup(accountID)
            } catch {
                // Still pending; the next retry tries again.
            }
        }
        persistPendingTokenCleanup()
        if pendingTokenCleanup.isEmpty { tokenCleanupNotice = nil }
    }

    // MARK: - Refresh

    @discardableResult
    func refresh(force: Bool = false) async -> RefreshOutcome {
        guard let account = selectedAccount else { return .signedOut }
        // A rejected token is not worth another request.
        if authIssue != nil { return .requiresReauthentication }
        guard !isRefreshing else { return .skipped }
        if let deadline = rateLimit?.deadline {
            if Date() < deadline { return .skipped }
            rateLimit = nil
        }
        guard force || Date().timeIntervalSince(lastRefreshAt) >= Self.minRefreshInterval else {
            return .skipped
        }
        let generation = sessionGeneration
        refreshCounter += 1
        let refreshID = refreshCounter
        activeRefreshID = refreshID
        isRefreshing = true
        // Count failed attempts too: an error must not be hammered either.
        lastRefreshAt = Date()
        defer {
            if activeRefreshID == refreshID {
                activeRefreshID = nil
                isRefreshing = false
            }
        }

        do {
            let response = try await withValidToken(for: account, generation: generation) { token, scopes in
                try await usageClient.fetchUsage(accessToken: token, scopes: scopes)
            }
            guard isCurrent(account, generation: generation) else { return .skipped }
            display = UsageDisplay(response)
            lastError = nil
            rateLimit = nil
            return .updated
        } catch APIError.rateLimited(let retryAfter) {
            guard isCurrent(account, generation: generation) else { return .skipped }
            let delay = max(retryAfter ?? 0, Self.rateLimitFallback)
            let deadline = Date().addingTimeInterval(delay)
            rateLimit = RateLimit(deadline: deadline)
            lastError = APIError.rateLimited(retryAfter: retryAfter).localizedDescription
            return .rateLimited(retryAfter)
        } catch APIError.unauthorized {
            // The rotation retry has already run; the token is really rejected.
            guard isCurrent(account, generation: generation) else { return .skipped }
            lastError = APIError.unauthorized.localizedDescription
            setAuthIssue(.sessionExpired)
            return .requiresReauthentication
        } catch APIError.noStoredToken {
            guard isCurrent(account, generation: generation) else { return .skipped }
            lastError = APIError.noStoredToken.localizedDescription
            setAuthIssue(.missingToken)
            return .requiresReauthentication
        } catch APIError.forbidden(let scopes) {
            // The token is valid; the server refuses the usage read. A fresh
            // sign-in can fix stale scopes, but not a plan-level block.
            guard isCurrent(account, generation: generation) else { return .skipped }
            lastError = APIError.forbidden(scopes: scopes).localizedDescription
            setAuthIssue(.forbidden)
            return .requiresReauthentication
        } catch {
            guard isCurrent(account, generation: generation) else { return .skipped }
            // Sleep, sign-out and wake cancel the waiting request; that is not
            // an error to show or to keep in state.
            if error is CancellationError || Task.isCancelled { return .skipped }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return .skipped
            }
            lastError = error.localizedDescription
            return .failed
        }
    }

    /// Refreshes before expiry, and once more if the server rejects the token
    /// anyway (clock skew, early revocation).
    private func withValidToken<T: Sendable>(for account: Account,
                                             generation: Int,
                                             _ body: (String, [String]) async throws -> T) async throws -> T {
        guard var pair = try cachedToken(for: account) else {
            throw APIError.noStoredToken
        }

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

    private func cachedToken(for account: Account) throws -> TokenPair? {
        if let cached = tokenCache[account.id] { return cached }
        let stored = try tokenStore.load(for: account.id)
        tokenCache[account.id] = stored
        return stored
    }

    /// Writes the new pair before dropping the old one, so a crash mid-rotation
    /// leaves a usable token.
    private func rotate(_ pair: TokenPair,
                        for account: Account,
                        generation: Int) async throws -> TokenPair {
        do {
            let refreshed = try await oauth.refresh(pair)
            guard isCurrent(account, generation: generation),
                  tokenCache[account.id]?.refreshToken == pair.refreshToken else {
                throw CancellationError()
            }
            try tokenStore.save(refreshed, for: account.id)
            tokenCache[account.id] = refreshed
            return refreshed
        } catch OAuthError.invalidGrant {
            guard isCurrent(account, generation: generation),
                  tokenCache[account.id]?.refreshToken == pair.refreshToken else {
                throw OAuthError.invalidGrant
            }
            do {
                try tokenStore.delete(for: account.id)
                forgetPendingTokenCleanup(account.id)
            } catch {
                rememberPendingTokenCleanup(account.id)
                tokenCleanupNotice = Self.tokenCleanupNoticeText
            }
            tokenCache[account.id] = nil
            accounts.removeAll { $0.id == account.id }
            selectedAccountID = accounts.first?.id
            display = nil
            rateLimit = nil
            authIssue = nil
            lastError = OAuthError.invalidGrant.localizedDescription
            saveAccounts()
            notifySessionStateChange()
            throw OAuthError.invalidGrant
        }
    }

    private func isCurrent(_ account: Account, generation: Int) -> Bool {
        sessionGeneration == generation && selectedAccount?.id == account.id
    }

    private func invalidateActiveRefresh() {
        activeRefreshID = nil
        isRefreshing = false
    }

    // MARK: - Session signal

    private func notifySessionStateChange() {
        onSessionStateChange?(sessionState)
    }

    private func setAuthIssue(_ issue: AuthIssue?) {
        guard authIssue != issue else { return }
        authIssue = issue
        notifySessionStateChange()
    }

    // MARK: - Pending Keychain cleanup

    private func loadPendingTokenCleanup() {
        pendingTokenCleanup = defaults.stringArray(forKey: pendingTokenCleanupKey) ?? []
        tokenCleanupNotice = pendingTokenCleanup.isEmpty ? nil : Self.tokenCleanupNoticeText
    }

    private func rememberPendingTokenCleanup(_ accountID: String) {
        guard !pendingTokenCleanup.contains(accountID) else { return }
        pendingTokenCleanup.append(accountID)
        persistPendingTokenCleanup()
    }

    private func forgetPendingTokenCleanup(_ accountID: String) {
        let before = pendingTokenCleanup.count
        pendingTokenCleanup.removeAll { $0 == accountID }
        guard pendingTokenCleanup.count != before else { return }
        persistPendingTokenCleanup()
        if pendingTokenCleanup.isEmpty { tokenCleanupNotice = nil }
    }

    private func persistPendingTokenCleanup() {
        if pendingTokenCleanup.isEmpty {
            defaults.removeObject(forKey: pendingTokenCleanupKey)
        } else {
            defaults.set(pendingTokenCleanup, forKey: pendingTokenCleanupKey)
        }
    }

    // MARK: - Persistence (metadata only, never tokens)

    private func loadAccounts() {
        guard let data = defaults.data(forKey: accountsKey),
              let stored = try? JSONDecoder().decode([Account].self, from: data)
        else { return }
        accounts = stored
        selectedAccountID = Self.normalizedSelection(defaults.string(forKey: "selectedAccountID"),
                                                     accounts: stored)
    }

    static func normalizedSelection(_ saved: String?, accounts: [Account]) -> String? {
        if let saved, accounts.contains(where: { $0.id == saved }) { return saved }
        return accounts.first?.id
    }

    private func saveAccounts() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: accountsKey)
        defaults.set(selectedAccountID, forKey: "selectedAccountID")
    }
}
