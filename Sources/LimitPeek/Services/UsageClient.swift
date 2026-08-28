import Foundation
import os

struct UsageClient: Sendable {
    var session: URLSession = API.makeSession()

    func fetchUsage(accessToken: String, scopes: [String] = []) async throws -> UsageResponse {
        try await get(API.usage, accessToken: accessToken, scopes: scopes)
    }

    func fetchProfile(accessToken: String) async throws -> Account {
        let response: ProfileResponse = try await get(API.profile, accessToken: accessToken)
        return response.asAccount
    }

    private func get<T: Decodable>(_ url: URL,
                                   accessToken: String,
                                   scopes: [String] = []) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.malformedResponse }

        switch http.statusCode {
        case 200..<300:
            do {
                return try API.makeDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.malformedResponse
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(scopes: scopes)
        case 429:
            Self.logRateLimit(http, body: data)
            throw APIError.rateLimited(
                retryAfter: API.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        default:
            throw APIError.http(status: http.statusCode)
        }
    }

    private static let log = Logger(subsystem: "dev.nevermind.LimitPeek", category: "ratelimit")

    /// The server's own account of the limit, which is otherwise invisible:
    /// `Retry-After` alone has proved useless. Response headers and an error
    /// body only — the token is in the request, and never goes near this.
    private static func logRateLimit(_ response: HTTPURLResponse, body: Data) {
        let interesting = response.allHeaderFields
            .map { (name: "\($0.key)".lowercased(), value: "\($0.value)") }
            .filter { $0.name.contains("ratelimit") || $0.name.contains("retry")
                || $0.name.contains("request-id") || $0.name == "date" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name): \($0.value)" }
            .joined(separator: " | ")
        // Every name too, to prove nothing informative is being filtered out.
        let names = response.allHeaderFields.keys
            .map { "\($0)".lowercased() }.sorted().joined(separator: ",")
        let text = String(decoding: body.prefix(512), as: UTF8.self)
        log.error("""
            429 headers [\(interesting, privacy: .public)] \
            all [\(names, privacy: .public)] body [\(text, privacy: .public)]
            """)
    }
}
