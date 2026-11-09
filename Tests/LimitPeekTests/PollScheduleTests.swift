import Foundation
import Testing
@testable import LimitPeek

struct PollScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pollsEveryMinuteAndEveryFiveInLowPowerMode() {
        let schedule = PollSchedule()

        #expect(schedule.interval(isLowPowerMode: false) == 60)
        #expect(schedule.interval(isLowPowerMode: true) == 300)
    }

    @Test func slowsDownAfterARateLimitUntilAPollLands() {
        var schedule = PollSchedule()

        schedule.record(.rateLimited)
        #expect(schedule.interval(isLowPowerMode: false) == 300)

        schedule.record(.failed)
        schedule.record(.skipped)
        schedule.record(.signedOut)
        #expect(schedule.interval(isLowPowerMode: false) == 300)

        schedule.record(.updated)
        #expect(schedule.interval(isLowPowerMode: false) == 60)
    }

    @Test func nextPollCountsFromTheLastRequestWhoeverMadeIt() {
        let schedule = PollSchedule()

        #expect(schedule.nextPoll(after: now, rateLimitedUntil: nil, isLowPowerMode: false)
                == now.addingTimeInterval(60))
        #expect(schedule.nextPoll(after: now, rateLimitedUntil: nil, isLowPowerMode: true)
                == now.addingTimeInterval(300))
    }

    @Test func nextPollWaitsForALaterRateLimitDeadline() {
        let schedule = PollSchedule()

        let later = now.addingTimeInterval(600)
        #expect(schedule.nextPoll(after: now, rateLimitedUntil: later, isLowPowerMode: false) == later)

        let sooner = now.addingTimeInterval(30)
        #expect(schedule.nextPoll(after: now, rateLimitedUntil: sooner, isLowPowerMode: false)
                == now.addingTimeInterval(60))
    }

    @Test func nextPollIsDueAtOnceBeforeTheFirstRequest() {
        let schedule = PollSchedule()

        #expect(schedule.nextPoll(after: .distantPast, rateLimitedUntil: nil, isLowPowerMode: false) < .now)
    }
}
