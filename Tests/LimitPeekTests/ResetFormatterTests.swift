import Foundation
import Testing
@testable import LimitPeek

/// Pinned to en_US so the wording does not depend on the machine's region.
struct ResetFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let locale = Locale(identifier: "en_US")

    @Test func withinADayShowsTheClockTimeAndWhatIsLeft() {
        let resetsAt = now.addingTimeInterval(75 * 60)
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))

        #expect(text(resetsIn: 75 * 60) == "at \(time) (1h 15m)")
        #expect(text(resetsIn: 54 * 60)?.hasSuffix("(54m)") == true)
    }

    @Test func roundsWhatIsLeftUp() {
        #expect(text(resetsIn: 74 * 60 + 20)?.hasSuffix("(1h 15m)") == true)
        #expect(text(resetsIn: 20)?.hasSuffix("(1m)") == true)
    }

    @Test func withinAWeekShowsTheWeekdayAndTime() {
        let resetsAt = now.addingTimeInterval(2 * 86_400 + 3600)

        #expect(text(resetsIn: 2 * 86_400 + 3600)
                == resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale)))
    }

    @Test func furtherOutAndForCreditsShowsTheDate() {
        let farOut = now.addingTimeInterval(8 * 86_400)
        #expect(text(resetsIn: 8 * 86_400) == farOut.formatted(.dateTime.day().month(.abbreviated).locale(locale)))

        let soon = now.addingTimeInterval(3600)
        #expect(text(resetsIn: 3600, isCalendarDate: true)
                == soon.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
    }

    @Test func pastOrMissingResetsShowNothing() {
        #expect(text(resetsIn: nil) == nil)
        #expect(text(resetsIn: 0) == nil)
        #expect(text(resetsIn: -60) == nil)
    }

    @Test func spokenFormSpellsOutWhatIsLeft() {
        let spoken = ResetFormatter.string(for: row(resetsIn: 75 * 60), now: now, spoken: true, locale: locale)

        #expect(spoken?.hasSuffix(", in 1 hour, 15 minutes") == true)
    }

    private func row(resetsIn seconds: TimeInterval?, isCalendarDate: Bool = false) -> UsageDisplay.Row {
        UsageDisplay.Row(id: "session", kind: "session", title: "5-hour limit", percent: 42,
                         resetsAt: seconds.map { now.addingTimeInterval($0) },
                         resetIsCalendarDate: isCalendarDate)
    }

    private func text(resetsIn seconds: TimeInterval?, isCalendarDate: Bool = false) -> String? {
        ResetFormatter.string(for: row(resetsIn: seconds, isCalendarDate: isCalendarDate),
                              now: now, locale: locale)
    }
}
