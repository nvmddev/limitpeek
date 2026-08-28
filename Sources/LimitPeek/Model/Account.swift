import Foundation

/// One signed-in Claude account, stored without its token in UserDefaults.
/// The token pair lives in the Keychain, keyed by `id`.
struct Account: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var displayName: String
    var email: String
    var organizationName: String?

    var subtitle: String {
        organizationName.map { "\(displayName) · \($0)" } ?? displayName
    }
}

/// Wire format of GET /api/oauth/profile.
struct ProfileResponse: Decodable, Sendable {
    var account: AccountInfo
    var organization: OrganizationInfo?

    struct AccountInfo: Decodable, Sendable {
        var uuid: String
        var email: String
        var displayName: String?
        var fullName: String?
    }

    struct OrganizationInfo: Decodable, Sendable {
        var uuid: String?
        var name: String?
    }

    var asAccount: Account {
        Account(id: account.uuid,
                displayName: account.displayName ?? account.fullName ?? account.email,
                email: account.email,
                organizationName: organization?.name)
    }
}
