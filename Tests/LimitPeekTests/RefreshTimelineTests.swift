import Foundation
import SwiftUI
import Testing
@testable import LimitPeek

/// The 1 Hz cadence is only used while a countdown is actually running;
/// otherwise the popover redraws at the same 30 s cadence as a fixed schedule.
struct RefreshTimelineTests {
    @Test func ticksEverySecondWhileTheDeadlineIsAhead() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = start.addingTimeInterval(10)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: deadline,
                                                     mode: .normal) == 1)
        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(0.001),
                                                     mode: .normal) == 1)
    }

    @Test func ticksEveryThirtySecondsWhileTheDeadlineIsMoreThanAMinuteAway() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(120),
                                                     mode: .normal) == 30)
        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(61),
                                                     mode: .normal) == 30)
        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(60),
                                                     mode: .normal) == 1)
        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(59.999),
                                                     mode: .normal) == 1)
    }

    @Test func ticksEveryThirtySecondsAtTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start,
                                                     mode: .normal) == 30)
    }

    @Test func ticksEveryThirtySecondsPastTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(-1),
                                                     mode: .normal) == 30)
    }

    @Test func ticksEveryThirtySecondsWithoutADeadline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: nil,
                                                     mode: .normal) == 30)
    }

    @Test func lowFrequencyModeIgnoresTheDeadline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: start.addingTimeInterval(60),
                                                     mode: .lowFrequency) == 30)
        #expect(RefreshTimelineSchedule.tickInterval(after: start,
                                                     deadline: nil,
                                                     mode: .lowFrequency) == 30)
    }

    @Test func entriesAdvanceByTheTickInterval() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var iterator = RefreshTimelineSchedule(deadline: start.addingTimeInterval(10))
            .entries(from: start, mode: .normal)
            .makeIterator()

        #expect(iterator.next() == start)
        #expect(iterator.next() == start.addingTimeInterval(1))
        #expect(iterator.next() == start.addingTimeInterval(2))
    }

    @Test func entriesUseThirtySecondsUntilTheFinalMinute() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var iterator = RefreshTimelineSchedule(deadline: start.addingTimeInterval(120))
            .entries(from: start, mode: .normal)
            .makeIterator()

        #expect(iterator.next() == start)
        #expect(iterator.next() == start.addingTimeInterval(30))
        #expect(iterator.next() == start.addingTimeInterval(60))
        #expect(iterator.next() == start.addingTimeInterval(61))
    }

    @Test func entriesSlowDownOnceTheDeadlineHasPassed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var iterator = RefreshTimelineSchedule(deadline: start.addingTimeInterval(2))
            .entries(from: start, mode: .normal)
            .makeIterator()

        #expect(iterator.next() == start)
        #expect(iterator.next() == start.addingTimeInterval(1))
        #expect(iterator.next() == start.addingTimeInterval(2))
        #expect(iterator.next() == start.addingTimeInterval(32))
    }

    @Test func entriesUseThirtySecondsWithoutADeadline() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var iterator = RefreshTimelineSchedule(deadline: nil)
            .entries(from: start, mode: .normal)
            .makeIterator()

        #expect(iterator.next() == start)
        #expect(iterator.next() == start.addingTimeInterval(30))
    }
}
