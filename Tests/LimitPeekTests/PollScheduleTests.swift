import Testing
@testable import LimitPeek

struct PollScheduleTests {
    @Test func backsOffWithinTheAllowedRange() {
        var schedule = PollSchedule()

        #expect(schedule.nextDelay(after: .updated, isLowPowerMode: false) == 180)
        #expect(schedule.nextDelay(after: .rateLimited(nil), isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .rateLimited(nil), isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .updated, isLowPowerMode: false) == 180)
    }

    @Test func honorsRetryAfterWhenItIsLonger() {
        var schedule = PollSchedule()

        #expect(schedule.nextDelay(after: .rateLimited(600), isLowPowerMode: false) == 600)
        #expect(schedule.nextDelay(after: .rateLimited(30), isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .rateLimited(1e12), isLowPowerMode: false)
                == API.maximumRetryAfter)
    }

    @Test func holdsThePenaltyAcrossFailuresAndLowPowerMode() {
        var schedule = PollSchedule()

        #expect(schedule.nextDelay(after: .rateLimited(nil), isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .failed, isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .skipped, isLowPowerMode: false) == 300)
        #expect(schedule.nextDelay(after: .signedOut, isLowPowerMode: true) == 300)
        #expect(schedule.nextDelay(after: .updated, isLowPowerMode: false) == 180)
    }
}
