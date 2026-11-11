import Foundation
import Testing
@testable import LimitPeek

struct PollScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pollsEveryTwoMinutesAndEveryFiveInLowPowerMode() {
        #expect(interval(after: now, isLowPowerMode: false) == 120)
        #expect(interval(after: now, isLowPowerMode: true) == 300)
    }

    @Test func staysSlowForTwentyMinutesAfterARateLimit() {
        #expect(interval(after: now, rateLimitedAt: now) == 300)
        #expect(interval(after: now.addingTimeInterval(5 * 60), rateLimitedAt: now) == 300)
        #expect(interval(after: now.addingTimeInterval(19 * 60), rateLimitedAt: now) == 300)
        #expect(interval(after: now.addingTimeInterval(20 * 60), rateLimitedAt: now) == 120)
    }

    @Test func nextPollCountsFromTheLastRequestWhoeverMadeIt() {
        #expect(PollSchedule.nextPoll(after: now, rateLimitedAt: nil, rateLimitedUntil: nil, isLowPowerMode: false)
                == now.addingTimeInterval(120))
        #expect(PollSchedule.nextPoll(after: now, rateLimitedAt: nil, rateLimitedUntil: nil, isLowPowerMode: true)
                == now.addingTimeInterval(300))
    }

    @Test func nextPollWaitsForALaterRateLimitDeadline() {
        let later = now.addingTimeInterval(600)
        #expect(PollSchedule.nextPoll(after: now, rateLimitedAt: nil, rateLimitedUntil: later,
                                      isLowPowerMode: false) == later)

        let sooner = now.addingTimeInterval(30)
        #expect(PollSchedule.nextPoll(after: now, rateLimitedAt: nil, rateLimitedUntil: sooner,
                                      isLowPowerMode: false) == now.addingTimeInterval(120))
    }

    @Test func nextPollIsDueAtOnceBeforeTheFirstRequest() {
        #expect(PollSchedule.nextPoll(after: .distantPast, rateLimitedAt: nil, rateLimitedUntil: nil,
                                      isLowPowerMode: false) < .now)
    }

    private func interval(after lastRequest: Date, rateLimitedAt: Date? = nil,
                          isLowPowerMode: Bool = false) -> TimeInterval {
        PollSchedule.interval(after: lastRequest, rateLimitedAt: rateLimitedAt, isLowPowerMode: isLowPowerMode)
    }
}
