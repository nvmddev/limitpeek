import Foundation
import Security
import Testing
@testable import LimitPeek

/// `TokenPair` boundaries and the in-memory store. No `SecItem*` call is made:
/// the real `TokenStore` needs prompts and a signing identity, so its Keychain
/// plumbing is deliberately out of scope here.
struct TokenStoreTests {
    // MARK: - Expiry margin

    @Test func doesNotRefreshAtTheExactMargin() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let atMargin = pair(expiringAt: now.addingTimeInterval(300))

        #expect(!atMargin.needsRefresh(now: now))
    }

    @Test func refreshesJustInsideTheMargin() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let justInside = pair(expiringAt: now.addingTimeInterval(299.999))

        #expect(justInside.needsRefresh(now: now))
    }

    @Test func respectsACustomMargin() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        #expect(!pair(expiringAt: now.addingTimeInterval(60))
            .needsRefresh(now: now, margin: 60))
        #expect(pair(expiringAt: now.addingTimeInterval(59.9))
            .needsRefresh(now: now, margin: 60))
    }

    @Test func refreshesAnAlreadyExpiredToken() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        #expect(pair(expiringAt: now.addingTimeInterval(-1)).needsRefresh(now: now))
        #expect(pair(expiringAt: now.addingTimeInterval(-86_400)).needsRefresh(now: now))
    }

    // MARK: - Codable

    @Test func tokenPairRoundTripsThroughJSON() throws {
        let original = TokenPair(accessToken: "access-token",
                                 refreshToken: "refresh-token",
                                 expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                                 scopes: ["user:profile", "user:usage"])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TokenPair.self, from: data)

        #expect(decoded.accessToken == original.accessToken)
        #expect(decoded.refreshToken == original.refreshToken)
        #expect(abs(decoded.expiresAt.timeIntervalSince(original.expiresAt)) < 0.001)
        #expect(decoded.scopes == original.scopes)
    }

    @Test func tokenPairEncodesItsFieldsAsAJSONObject() throws {
        let data = try JSONEncoder().encode(pair(expiringAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["accessToken", "refreshToken", "expiresAt", "scopes"])
    }

    // MARK: - KeychainError

    @Test func keychainErrorDescriptionIncludesStatusAndMessage() throws {
        let error = KeychainError.status(errSecItemNotFound)
        let description = try #require(error.errorDescription)
        let message = SecCopyErrorMessageString(errSecItemNotFound, nil) as String? ?? "unknown"

        #expect(description == "Keychain error \(errSecItemNotFound): \(message)")
        #expect(description.contains("\(errSecItemNotFound)"))
        #expect(description.contains(message))
        #expect(!description.hasSuffix("unknown"))
    }

    // MARK: - InMemoryTokenStore

    @Test func inMemoryStoreReturnsNilForAnUnknownAccount() throws {
        let store = InMemoryTokenStore()

        #expect(try store.load(for: "missing") == nil)
        #expect(store.count == 0)
    }

    @Test func inMemoryStoreSavesLoadsAndOverwrites() throws {
        let store = InMemoryTokenStore()
        try store.save(pair(access: "old"), for: "account-1")
        try store.save(pair(access: "new"), for: "account-1")

        #expect(try store.load(for: "account-1")?.accessToken == "new")
        #expect(store.count == 1)
    }

    @Test func inMemoryStoreKeepsAccountsSeparate() throws {
        let store = InMemoryTokenStore()
        try store.save(pair(access: "one"), for: "account-1")
        try store.save(pair(access: "two"), for: "account-2")

        #expect(try store.load(for: "account-1")?.accessToken == "one")
        #expect(try store.load(for: "account-2")?.accessToken == "two")
        #expect(store.count == 2)
    }

    @Test func inMemoryStoreDeletesOneAccountAndToleratesAMissingOne() throws {
        let store = InMemoryTokenStore()
        try store.save(pair(access: "one"), for: "account-1")
        try store.save(pair(access: "two"), for: "account-2")

        try store.delete(for: "account-1")
        #expect(try store.load(for: "account-1") == nil)
        #expect(try store.load(for: "account-2")?.accessToken == "two")
        #expect(store.count == 1)

        try store.delete(for: "account-1")
        #expect(store.count == 1)
    }

    // MARK: - Helpers

    private func pair(expiringAt date: Date) -> TokenPair {
        pair(access: "access", expiringAt: date)
    }

    private func pair(access: String, expiringAt date: Date = Date()) -> TokenPair {
        TokenPair(accessToken: access,
                  refreshToken: "refresh",
                  expiresAt: date,
                  scopes: ["user:profile"])
    }
}
