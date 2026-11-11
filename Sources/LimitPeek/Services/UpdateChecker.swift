import Foundation
import Observation

/// Looks for a newer release on GitHub at launch and once a day after that.
@MainActor
@Observable
final class UpdateChecker {
    struct Release: Equatable, Sendable {
        let version: AppVersion
        let page: URL
    }

    /// Nil without a bundle version, as in `swift run`, which never checks.
    let current: AppVersion?
    /// Kept through failed checks, cleared once the installed build catches up.
    private(set) var available: Release?

    @ObservationIgnored private let client: ReleaseClient
    @ObservationIgnored private var task: Task<Void, Never>?

    init(current: String?, client: ReleaseClient = ReleaseClient()) {
        self.current = current.flatMap(AppVersion.init)
        self.client = client
    }

    func start() {
        guard task == nil, current != nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled {
            let interval: Duration = await check() ? .seconds(24 * 3600) : .seconds(3600)
            do {
                try await Task.sleep(for: interval, tolerance: .seconds(600))
            } catch {
                return
            }
        }
    }

    /// Whether GitHub answered.
    @discardableResult
    func check() async -> Bool {
        guard let current else { return false }
        do {
            let latest = try await client.latest()
            available = latest.version > current ? latest : nil
            return true
        } catch {
            return false
        }
    }
}

/// Fetches the newest published release. It sends no token and no account data.
struct ReleaseClient: Sendable {
    static let repository = "nvmddev/limitpeek"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    var session: URLSession = API.shared

    func latest() async throws -> UpdateChecker.Release {
        var request = URLRequest(url: Self.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.malformedResponse }
        guard http.statusCode == 200 else { throw APIError.http(status: http.statusCode) }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let version = AppVersion(body.tagName) else {
            throw APIError.malformedResponse
        }
        // Built here rather than taken from the response, so the menu can only
        // ever open this repository's release page.
        let page = URL(string: "https://github.com/\(Self.repository)/releases/tag/v\(version)")!
        return UpdateChecker.Release(version: version, page: page)
    }

    private struct Body: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}

/// MAJOR.MINOR.PATCH, as the release tags and the bundle carry it, with or
/// without the tag's leading "v".
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        let parts = string.dropFirst(string.hasPrefix("v") ? 1 : 0)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        components = numbers
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }
}

extension Bundle {
    var shortVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
