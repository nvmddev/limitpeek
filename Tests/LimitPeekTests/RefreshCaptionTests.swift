import Foundation
import Testing
@testable import LimitPeek

/// The Refresh item's subtitle, and how often it changes while the menu is open.
struct RefreshCaptionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func ticksEverySecondInTheFinalMinuteBeforeADeadline() {
        #expect(tick(deadline: start.addingTimeInterval(10)) == 1)
        #expect(tick(deadline: start.addingTimeInterval(60)) == 1)
        #expect(tick(deadline: start.addingTimeInterval(59.999)) == 1)
        #expect(tick(deadline: start.addingTimeInterval(0.001)) == 1)
    }

    @Test func ticksEveryThirtySecondsOtherwise() {
        #expect(tick(deadline: start.addingTimeInterval(61)) == 30)
        #expect(tick(deadline: start.addingTimeInterval(120)) == 30)
        #expect(tick(deadline: start) == 30)
        #expect(tick(deadline: start.addingTimeInterval(-1)) == 30)
        #expect(tick(deadline: nil) == 30)
    }

    @Test func refreshingWinsOverEverythingElse() {
        #expect(text(isRefreshing: true, rateLimitedUntil: start.addingTimeInterval(300),
                     fetchedAt: start) == "Updating…")
    }

    @Test func countsDownARateLimit() {
        let caption = text(rateLimitedUntil: start.addingTimeInterval(272), fetchedAt: start)
        #expect(caption?.hasPrefix("Rate limited · retrying in ") == true)
    }

    @Test func dropsTheCountdownInItsFinalSecond() {
        #expect(text(rateLimitedUntil: start.addingTimeInterval(0.5),
                     fetchedAt: start.addingTimeInterval(-10)) == "Updated just now")
    }

    @Test func saysHowOldTheReadingIs() {
        #expect(text(fetchedAt: start.addingTimeInterval(-59)) == "Updated just now")
        let now = Date.now
        let older = RefreshCaption.text(isRefreshing: false, rateLimitedUntil: nil,
                                        fetchedAt: now.addingTimeInterval(-120), now: now)
        #expect(older?.hasPrefix("Updated ") == true)
        #expect(older != "Updated just now")
    }

    @Test func saysNothingBeforeTheFirstReading() {
        #expect(text(fetchedAt: nil) == nil)
    }

    private func tick(deadline: Date?) -> TimeInterval {
        RefreshCaption.tickInterval(after: start, deadline: deadline)
    }

    private func text(isRefreshing: Bool = false, rateLimitedUntil: Date? = nil, fetchedAt: Date?) -> String? {
        RefreshCaption.text(isRefreshing: isRefreshing, rateLimitedUntil: rateLimitedUntil,
                            fetchedAt: fetchedAt, now: start)
    }
}
