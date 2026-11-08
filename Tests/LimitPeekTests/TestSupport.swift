import Foundation
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

final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var pairs: [String: TokenPair] = [:]

    func save(_ pair: TokenPair, for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        pairs[accountID] = pair
    }

    func load(for accountID: String) throws -> TokenPair? {
        lock.lock()
        defer { lock.unlock() }
        return pairs[accountID]
    }

    func delete(for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        pairs[accountID] = nil
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pairs.count
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
