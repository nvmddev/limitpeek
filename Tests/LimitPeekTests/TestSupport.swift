import Foundation
import os
import Testing
@testable import LimitPeek

final class StubURLProtocol: URLProtocol {
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

final class InMemoryTokenStore: TokenStoring {
    private let pairs = OSAllocatedUnfairLock<[String: TokenPair]>(initialState: [:])

    func save(_ pair: TokenPair, for accountID: String) throws {
        pairs.withLock { $0[accountID] = pair }
    }

    func load(for accountID: String) throws -> TokenPair? {
        pairs.withLock { $0[accountID] }
    }

    func delete(for accountID: String) throws {
        pairs.withLock { $0[accountID] = nil }
    }

    var count: Int {
        pairs.withLock { $0.count }
    }
}

/// Counts calls from URL loading threads.
final class LockedCounter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)

    @discardableResult
    func increment() -> Int {
        value.withLock { value in
            value += 1
            return value
        }
    }

    var current: Int {
        value.withLock { $0 }
    }
}

func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

func makeStubResponse(for request: URLRequest,
                      status: Int = 200,
                      body: String,
                      headers: [String: String]? = nil) throws -> (HTTPURLResponse, Data) {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url,
                                                statusCode: status,
                                                httpVersion: nil,
                                                headerFields: headers))
    return (response, Data(body.utf8))
}
