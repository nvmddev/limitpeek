import Foundation

enum API {
    static let base = URL(string: "https://api.anthropic.com")!
    static let usage = base.appending(path: "api/oauth/usage")
    static let profile = base.appending(path: "api/oauth/profile")

    /// No cookies, no disk cache: none of this traffic outlives the process.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = true
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unrecognised timestamp: \(raw)"))
            }
            return date
        }
        return decoder
    }

    /// The API returns microseconds, which ISO8601DateFormatter rejects.
    /// Truncate to milliseconds, then fall back to whole seconds.
    static func parseTimestamp(_ raw: String) -> Date? {
        var value = raw
        if let dot = value.firstIndex(of: ".") {
            let afterDot = value.index(after: dot)
            let digits = value[afterDot...].prefix(while: \.isNumber)
            if digits.count > 3 {
                let keep = value.index(afterDot, offsetBy: 3)
                value.removeSubrange(keep..<value.index(afterDot, offsetBy: digits.count))
            }
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    /// `Retry-After` is either a count of seconds or an HTTP date. The endpoint
    /// has been seen sending 0, which is no answer at all — anything under a
    /// second is treated as absent so the caller falls back to its own backoff.
    static func parseRetryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) { return seconds >= 1 ? seconds : nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: raw) else { return nil }
        let seconds = date.timeIntervalSinceNow
        return seconds >= 1 ? seconds : nil
    }
}

enum APIError: Error, LocalizedError {
    /// 401: stale token, refreshing may fix it.
    case unauthorized
    /// 403: valid token, wrong scopes. Refreshing cannot fix it.
    case forbidden(scopes: [String])
    case noStoredToken
    /// 429: polling faster than the endpoint allows.
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Sign-in expired."
        case .forbidden(let scopes):
            "Not permitted to read usage (scopes: \(scopes.joined(separator: ", "))). Sign out and in again."
        case .noStoredToken:
            "No saved sign-in found. Sign out and in again."
        case .rateLimited:
            "Rate limited by Claude. Retrying automatically."
        case .http(let status):
            "Server returned \(status)."
        case .malformedResponse:
            "Unexpected response from Claude."
        }
    }
}
