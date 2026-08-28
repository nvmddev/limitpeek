import CryptoKit
import Foundation

enum OAuth {
    /// Public PKCE client. No secret: the verifier never leaves this process.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    /// Out-of-band redirect: the browser shows a code to paste back. A loopback
    /// listener instead would need the network.server entitlement.
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"

    /// Read-only. A token scoped this way cannot spend inference if it leaks.
    static let scopes = ["user:profile"]

    /// Only if the usage endpoint rejects a profile-only token.
    static let fallbackScopes = ["user:profile", "user:inference"]
}

struct PKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String

    init() {
        verifier = Self.randomURLSafeString()
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        state = Self.randomURLSafeString()
    }

    private static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // The CSPRNG. Never Int.random for this.
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

enum OAuthError: Error, LocalizedError {
    case invalidGrant
    case server(String)
    case malformedCode

    var errorDescription: String? {
        switch self {
        case .invalidGrant: "This sign-in has expired. Please sign in again."
        case .server(let message): message
        case .malformedCode: "That code doesn't look right. Copy the whole value from the page."
        }
    }
}

struct OAuthService: Sendable {
    var session: URLSession = API.makeSession()
    var scopes: [String] = OAuth.scopes

    func authorizationURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: OAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: OAuth.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: OAuth.redirectURI),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state)
        ]
        return components.url!
    }

    /// The callback page shows `code#state`; accept that or a bare code.
    func exchange(pastedCode: String, pkce: PKCE) async throws -> TokenPair {
        let trimmed = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OAuthError.malformedCode }

        let parts = trimmed.split(separator: "#", maxSplits: 1)
        let code = String(parts[0])
        let state = parts.count > 1 ? String(parts[1]) : pkce.state

        return try await requestToken(body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuth.redirectURI,
            "client_id": OAuth.clientID,
            "code_verifier": pkce.verifier,
            "state": state
        ], fallbackRefreshToken: nil)
    }

    func refresh(_ pair: TokenPair) async throws -> TokenPair {
        try await requestToken(body: [
            "grant_type": "refresh_token",
            "refresh_token": pair.refreshToken,
            "client_id": OAuth.clientID,
            "scope": pair.scopes.joined(separator: " ")
        ], fallbackRefreshToken: pair.refreshToken)
    }

    private struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Double?
        var scope: String?
    }

    private struct ErrorResponse: Decodable {
        var error: String?
        var errorDescription: String?
    }

    /// Both grants POST JSON, not form-encoded, to the same endpoint.
    private func requestToken(body: [String: String],
                              fallbackRefreshToken: String?) async throws -> TokenPair {
        var request = URLRequest(url: OAuth.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.malformedResponse }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard (200..<300).contains(http.statusCode) else {
            let failure = try? decoder.decode(ErrorResponse.self, from: data)
            if failure?.error == "invalid_grant" { throw OAuthError.invalidGrant }
            throw OAuthError.server(failure?.errorDescription
                                    ?? failure?.error
                                    ?? "Sign-in failed (\(http.statusCode)).")
        }

        let token = try decoder.decode(TokenResponse.self, from: data)
        // A refresh may omit refresh_token, meaning "keep the old one".
        guard let refreshToken = token.refreshToken ?? fallbackRefreshToken else {
            throw APIError.malformedResponse
        }

        return TokenPair(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(token.expiresIn ?? 3600),
            scopes: token.scope?.split(separator: " ").map(String.init) ?? scopes
        )
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
