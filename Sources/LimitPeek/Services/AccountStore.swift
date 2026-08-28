import Foundation
import Observation

/// Owns accounts, tokens and the current reading. Views observe this and
/// nothing else. Shaped for multiple accounts even though the UI shows one.
@MainActor
@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []
    var selectedAccountID: String?
    private(set) var display: UsageDisplay?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    /// Set while a sign-in is in flight, to verify the pasted code against the
    /// challenge that started it.
    private(set) var pendingPKCE: PKCE?

    /// Read from the Keychain once per launch. macOS authorises reads
    /// individually, so hitting it on every poll meant a prompt on every poll.
    private var tokenCache: [String: TokenPair] = [:]

    private let usageClient = UsageClient()
    private let oauth = OAuthService()
    private let defaults = UserDefaults.standard
    private let accountsKey = "accounts"

    var selectedAccount: Account? {
        accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    var isSignedIn: Bool { selectedAccount != nil }

    init() {
        loadAccounts()
    }

    // MARK: - Sign in

    func beginSignIn() -> URL {
        let pkce = PKCE()
        pendingPKCE = pkce
        return oauth.authorizationURL(pkce: pkce)
    }

    func cancelSignIn() {
        pendingPKCE = nil
    }

    func completeSignIn(pastedCode: String) async {
        guard let pkce = pendingPKCE else { return }
        lastError = nil
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let pair = try await oauth.exchange(pastedCode: pastedCode, pkce: pkce)
            let account = try await usageClient.fetchProfile(accessToken: pair.accessToken)
            try TokenStore.save(pair, for: account.id)
            tokenCache[account.id] = pair

            accounts.removeAll { $0.id == account.id }
            accounts.append(account)
            selectedAccountID = account.id
            saveAccounts()
            pendingPKCE = nil

            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        guard let account = selectedAccount else { return }
        try? TokenStore.delete(for: account.id)
        tokenCache[account.id] = nil
        accounts.removeAll { $0.id == account.id }
        selectedAccountID = accounts.first?.id
        display = nil
        saveAccounts()
    }

    // MARK: - Refresh

    func refresh() async {
        guard let account = selectedAccount else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await withValidToken(for: account) { token, scopes in
                try await usageClient.fetchUsage(accessToken: token, scopes: scopes)
            }
            display = UsageDisplay(response)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Refreshes before expiry, and once more if the server rejects the token
    /// anyway (clock skew, early revocation).
    private func withValidToken<T>(for account: Account,
                                   _ body: (String, [String]) async throws -> T) async throws -> T {
        guard var pair = try cachedToken(for: account) else {
            throw APIError.noStoredToken
        }

        if pair.needsRefresh() {
            pair = try await rotate(pair, for: account)
        }

        do {
            return try await body(pair.accessToken, pair.scopes)
        } catch APIError.unauthorized {
            // Only a 401 is worth retrying: a 403 means the scopes are wrong,
            // and a fresh token carries the same ones.
            let rotated = try await rotate(pair, for: account)
            return try await body(rotated.accessToken, rotated.scopes)
        }
    }

    private func cachedToken(for account: Account) throws -> TokenPair? {
        if let cached = tokenCache[account.id] { return cached }
        let stored = try TokenStore.load(for: account.id)
        tokenCache[account.id] = stored
        return stored
    }

    /// Writes the new pair before dropping the old one, so a crash mid-rotation
    /// leaves a usable token.
    private func rotate(_ pair: TokenPair, for account: Account) async throws -> TokenPair {
        do {
            let refreshed = try await oauth.refresh(pair)
            try TokenStore.save(refreshed, for: account.id)
            tokenCache[account.id] = refreshed
            return refreshed
        } catch OAuthError.invalidGrant {
            try? TokenStore.delete(for: account.id)
            tokenCache[account.id] = nil
            accounts.removeAll { $0.id == account.id }
            selectedAccountID = accounts.first?.id
            display = nil
            saveAccounts()
            throw OAuthError.invalidGrant
        }
    }

    // MARK: - Persistence (metadata only, never tokens)

    private func loadAccounts() {
        guard let data = defaults.data(forKey: accountsKey),
              let stored = try? JSONDecoder().decode([Account].self, from: data)
        else { return }
        accounts = stored
        selectedAccountID = defaults.string(forKey: "selectedAccountID") ?? stored.first?.id
    }

    private func saveAccounts() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: accountsKey)
        defaults.set(selectedAccountID, forKey: "selectedAccountID")
    }
}
