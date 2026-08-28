import Foundation

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
        default:
            throw APIError.http(status: http.statusCode)
        }
    }
}
