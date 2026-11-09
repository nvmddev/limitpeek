import Foundation
import os
import Testing
@testable import LimitPeek

/// Error mapping and success decoding of `UsageClient`, driven through a
/// suite-local `URLProtocol` so it shares no state with `StubURLProtocol` or
/// `AccountStoreRaceTests` and can run beside them.
@Suite(.serialized)
struct UsageClientTests {
    @Test func mapsUnauthorizedStatus() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 401,
                                  body: #"{"error":"unauthorized"}"#)
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // Expected.
        }
    }

    @Test func mapsForbiddenStatusWithScopes() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 403,
                                  body: #"{"error":"forbidden"}"#)
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token",
                                            scopes: ["user:profile", "user:usage"])
            Issue.record("Expected APIError.forbidden")
        } catch APIError.forbidden(let scopes) {
            #expect(scopes == ["user:profile", "user:usage"])
        }
    }

    @Test func mapsForbiddenStatusWithoutScopes() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 403, body: "{}")
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.forbidden")
        } catch APIError.forbidden(let scopes) {
            #expect(scopes.isEmpty)
        }
    }

    @Test func mapsRateLimitWithRetryAfterSeconds() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 429,
                                  body: #"{"error":"rate limited"}"#,
                                  headers: ["Retry-After": "120"])
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.rateLimited")
        } catch APIError.rateLimited(let retryAfter) {
            #expect(retryAfter == 120)
        }
    }

    @Test func mapsRateLimitWithRetryAfterHTTPDate() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let retryDate = formatter.string(from: Date().addingTimeInterval(120))

        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 429,
                                  body: #"{"error":"rate limited"}"#,
                                  headers: ["Retry-After": retryDate])
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.rateLimited")
        } catch APIError.rateLimited(let retryAfter) {
            let seconds = try #require(retryAfter)
            #expect(seconds > 60)
            #expect(seconds <= 120)
        }
    }

    @Test func mapsRateLimitWithoutRetryAfter() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 429, body: "{}")
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.rateLimited")
        } catch APIError.rateLimited(let retryAfter) {
            #expect(retryAfter == nil)
        }
    }

    @Test func mapsMalformedSuccessBody() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 200, body: "not json")
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.malformedResponse")
        } catch APIError.malformedResponse {
            // Expected.
        }
    }

    @Test func mapsServerErrorStatus() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 500, body: "{}")
        }
        defer { UsageStubURLProtocol.handler = nil }

        do {
            _ = try await client.fetchUsage(accessToken: "token")
            Issue.record("Expected APIError.http")
        } catch APIError.http(let status) {
            #expect(status == 500)
        }
    }

    @Test func decodesUsageOnSuccess() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 200, body: """
            {"limits":[{"kind":"session","percent":42,"resets_at":null}]}
            """)
        }
        defer { UsageStubURLProtocol.handler = nil }

        let response = try await client.fetchUsage(accessToken: "token")
        #expect(response.limits.count == 1)
        #expect(response.limits.first?.kind == "session")
        #expect(response.limits.first?.percent == 42)
    }

    @Test func decodesProfileOnSuccess() async throws {
        let client = makeUsageClient { request in
            try usageStubResponse(for: request, status: 200, body: """
            {"account":{"uuid":"account-1","email":"alex@example.com",
                        "display_name":"Alex"},
             "organization":{"name":"Acme"}}
            """)
        }
        defer { UsageStubURLProtocol.handler = nil }

        let account = try await client.fetchProfile(accessToken: "token")
        #expect(account.id == "account-1")
        #expect(account.displayName == "Alex")
        #expect(account.organizationName == "Acme")
    }

    @Test func sendsBearerTokenAndJSONAcceptHeader() async throws {
        let recorder = UsageRequestRecorder()
        let client = makeUsageClient { request in
            recorder.record(request)
            return try usageStubResponse(for: request, status: 200, body: "{}")
        }
        defer { UsageStubURLProtocol.handler = nil }

        _ = try await client.fetchUsage(accessToken: "secret")

        let request = try #require(recorder.request)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}

// MARK: - Suite-local stub

private final class UsageStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class UsageRequestRecorder: Sendable {
    private let stored = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)

    func record(_ request: URLRequest) {
        stored.withLock { $0 = request }
    }

    var request: URLRequest? {
        stored.withLock { $0 }
    }
}

private func makeUsageClient(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> UsageClient {
    UsageStubURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageStubURLProtocol.self]
    configuration.timeoutIntervalForRequest = 15
    return UsageClient(session: URLSession(configuration: configuration))
}

private func usageStubResponse(for request: URLRequest,
                               status: Int = 200,
                               body: String,
                               headers: [String: String]? = nil) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url,
                                         statusCode: status,
                                         httpVersion: "HTTP/1.1",
                                         headerFields: headers) else {
        throw URLError(.badURL)
    }
    return (response, Data(body.utf8))
}
