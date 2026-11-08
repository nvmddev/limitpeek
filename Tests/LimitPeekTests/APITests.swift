import Foundation
import Testing
@testable import LimitPeek

struct APITests {
    @Test func parsesRetryAfterSeconds() {
        #expect(API.parseRetryAfter("120") == 120)
        #expect(API.parseRetryAfter(" 120 ") == 120)
        #expect(API.parseRetryAfter("1") == 1)
        #expect(API.parseRetryAfter("0") == nil)
        #expect(API.parseRetryAfter("0.5") == nil)
        #expect(API.parseRetryAfter("-10") == nil)
        #expect(API.parseRetryAfter("garbage") == nil)
        #expect(API.parseRetryAfter("") == nil)
        #expect(API.parseRetryAfter(nil) == nil)
    }

    @Test func capsUnreasonableRetryAfterValues() {
        #expect(API.parseRetryAfter("inf") == nil)
        #expect(API.parseRetryAfter("1e30") == API.maximumRetryAfter)
    }

    @Test func parsesRetryAfterHTTPDates() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        let future = formatter.string(from: Date().addingTimeInterval(120))
        #expect((API.parseRetryAfter(future) ?? 0) > 60)

        let past = formatter.string(from: Date().addingTimeInterval(-120))
        #expect(API.parseRetryAfter(past) == nil)
    }

    @Test func refreshesOnlyInsideTheExpiryMargin() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        func pair(secondsLeft: TimeInterval) -> TokenPair {
            TokenPair(accessToken: "a", refreshToken: "r",
                      expiresAt: now.addingTimeInterval(secondsLeft), scopes: [])
        }

        #expect(!pair(secondsLeft: 301).needsRefresh(now: now))
        #expect(pair(secondsLeft: 299).needsRefresh(now: now))
        #expect(pair(secondsLeft: -1).needsRefresh(now: now))
        #expect(!pair(secondsLeft: 300).needsRefresh(now: now))
    }
}
