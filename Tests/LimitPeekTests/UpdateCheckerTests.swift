import Foundation
import os
import Testing
@testable import LimitPeek

struct AppVersionTests {
    @Test(arguments: ["0.2.2", "v0.2.2"])
    func parsesWithOrWithoutTagPrefix(_ raw: String) throws {
        let version = try #require(AppVersion(raw))
        #expect(version.components == [0, 2, 2])
        #expect(version.description == "0.2.2")
    }

    @Test(arguments: ["", "v", "1.2", "1.2.3.4", "1.2.x", "1..3", "+1.2.3", "1.-2.3", "1.2.3-beta", "V1.2.3", "1.2.٣"])
    func rejectsAnythingButThreeNumbers(_ raw: String) {
        #expect(AppVersion(raw) == nil)
    }

    @Test func comparesNumericallyNotAlphabetically() throws {
        let order = try ["0.2.9", "0.2.10", "0.10.0", "1.0.0"].map { try #require(AppVersion($0)) }
        #expect(order == order.sorted())
        #expect(try #require(AppVersion("v0.2.2")) == #require(AppVersion("0.2.2")))
    }
}

/// Driven through a suite-local `URLProtocol`, like `UsageClientTests`, so it
/// shares no stub state with other suites.
@MainActor
@Suite(.serialized)
struct UpdateCheckerTests {
    @Test func offersANewerRelease() async throws {
        let checker = makeChecker(current: "0.2.2") { try releaseResponse(for: $0, tag: "v0.3.0") }
        defer { ReleaseStubURLProtocol.handler = nil }

        #expect(await checker.check())
        let release = try #require(checker.available)
        #expect(release.version.description == "0.3.0")
        #expect(release.page.absoluteString == "https://github.com/nvmddev/limitpeek/releases/tag/v0.3.0")
    }

    @Test(arguments: ["v0.2.2", "v0.2.1"])
    func offersNothingWhenUpToDateOrAhead(_ tag: String) async {
        let checker = makeChecker(current: "0.2.2") { try releaseResponse(for: $0, tag: tag) }
        defer { ReleaseStubURLProtocol.handler = nil }

        #expect(await checker.check())
        #expect(checker.available == nil)
    }

    @Test func keepsTheOfferThroughAFailedCheck() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let checker = makeChecker(current: "0.2.2") { request in
            let call = calls.withLock { $0 += 1; return $0 }
            return try call == 1 ? releaseResponse(for: request, tag: "v0.3.0")
                                 : releaseResponse(for: request, status: 403, body: "{}")
        }
        defer { ReleaseStubURLProtocol.handler = nil }

        #expect(await checker.check())
        #expect(await !checker.check())
        #expect(checker.available?.version.description == "0.3.0")
    }

    @Test func clearsTheOfferOnceUpToDate() async {
        let latest = OSAllocatedUnfairLock(initialState: "v0.3.0")
        let checker = makeChecker(current: "0.3.0") { request in
            try releaseResponse(for: request, tag: latest.withLock { $0 })
        }
        defer { ReleaseStubURLProtocol.handler = nil }

        latest.withLock { $0 = "v0.3.1" }
        await checker.check()
        #expect(checker.available != nil)
        latest.withLock { $0 = "v0.3.0" }
        await checker.check()
        #expect(checker.available == nil)
    }

    @Test(arguments: [#"{"tag_name":"nightly"}"#, #"{"name":"v9.0.0"}"#, "not json"])
    func rejectsAMalformedRelease(_ body: String) async {
        let checker = makeChecker(current: "0.2.2") { try releaseResponse(for: $0, status: 200, body: body) }
        defer { ReleaseStubURLProtocol.handler = nil }

        #expect(await !checker.check())
        #expect(checker.available == nil)
    }

    @Test func neverChecksWithoutAVersionOfItsOwn() async {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let checker = makeChecker(current: nil) { request in
            calls.withLock { $0 += 1 }
            return try releaseResponse(for: request, tag: "v9.0.0")
        }
        defer { ReleaseStubURLProtocol.handler = nil }

        #expect(await !checker.check())
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func asksGitHubAnonymously() async throws {
        let recorded = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let checker = makeChecker(current: "0.2.2") { request in
            recorded.withLock { $0 = request }
            return try releaseResponse(for: request, tag: "v0.2.2")
        }
        defer { ReleaseStubURLProtocol.handler = nil }

        await checker.check()
        let request = try #require(recorded.withLock { $0 })
        #expect(request.url?.absoluteString == "https://api.github.com/repos/nvmddev/limitpeek/releases/latest")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }
}

// MARK: - Suite-local stub

private final class ReleaseStubURLProtocol: URLProtocol {
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

@MainActor
private func makeChecker(
    current: String?,
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> UpdateChecker {
    ReleaseStubURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ReleaseStubURLProtocol.self]
    return UpdateChecker(current: current,
                         client: ReleaseClient(session: URLSession(configuration: configuration)))
}

private func releaseResponse(for request: URLRequest, tag: String) throws -> (HTTPURLResponse, Data) {
    try releaseResponse(for: request, status: 200,
                        body: #"{"tag_name":"\#(tag)","html_url":"https://example.com/elsewhere"}"#)
}

private func releaseResponse(for request: URLRequest, status: Int, body: String) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                         headerFields: nil) else {
        throw URLError(.badURL)
    }
    return (response, Data(body.utf8))
}
