import Foundation
import Testing
@testable import LimitPeek

/// The usage endpoint is undocumented, so these tests pin the parts of its shape
/// the app depends on against a real captured response.
struct UsageDecodingTests {

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func decodesRealResponse() throws {
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Self.fixture("usage"))

        // Named buckets: utilization is a 0-100 percentage, not a 0-1 fraction.
        let fiveHour = try #require(response.fiveHour?.utilization)
        #expect(fiveHour > 1 && fiveHour <= 100)
        #expect(response.fiveHour?.resetsAt != nil)

        // Buckets the account does not have decode as nil rather than failing.
        #expect(response.sevenDayOpus == nil)

        // The generic array is present and carries the session window.
        #expect(response.limits.contains { $0.kind == "session" })
        #expect(response.limits.contains { $0.kind == "weekly_all" })

        // Money arrives in minor units with an explicit exponent.
        let spend = try #require(response.spend)
        #expect(spend.limit?.amount == Decimal(15))
        #expect(spend.used?.currency == "USD")
    }

    @Test func parsesMicrosecondTimestamps() throws {
        // The API returns 6 fractional digits, which ISO8601DateFormatter rejects
        // unless they are truncated first.
        let date = try #require(API.parseTimestamp("2026-08-27T16:19:59.900162+00:00"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let expected = try #require(utc.date(from: DateComponents(
            year: 2026, month: 8, day: 27, hour: 16, minute: 19, second: 59)))
        #expect(abs(date.timeIntervalSince(expected) - 0.9) < 0.01)

        // Whole seconds must still parse.
        #expect(API.parseTimestamp("2026-08-27T16:19:59Z") != nil)
        #expect(API.parseTimestamp("not a date") == nil)
    }

    @Test func buildsDisplayRowsFromLimits() throws {
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Self.fixture("usage"))
        let display = UsageDisplay(response)

        #expect(display.rows.first?.title == "5-hour limit")
        #expect(display.rows.contains { $0.title == "Weekly · all models" })
        #expect(display.sessionPercent == response.fiveHour?.utilization)

        let credits = try #require(display.rows.first { $0.id == "credits" })
        #expect(credits.detail?.contains("15") == true)
        #expect(credits.resetIsCalendarDate)
    }

    @Test func creditsResetOnTheFirstOfNextMonth() throws {
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Self.fixture("usage"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))

        let august27 = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let display = UsageDisplay(response, fetchedAt: august27, calendar: calendar)
        let credits = try #require(display.rows.first { $0.id == "credits" })

        let components = calendar.dateComponents([.year, .month, .day], from: try #require(credits.resetsAt))
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 1)
    }

    @Test func fallsBackToNamedBucketsWhenLimitsIsEmpty() throws {
        let json = """
        {"five_hour": {"utilization": 42.0, "resets_at": "2026-08-27T16:19:59.900162+00:00"},
         "seven_day": {"utilization": 12.0, "resets_at": null},
         "limits": []}
        """
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        let display = UsageDisplay(response)

        #expect(display.rows.count == 2)
        #expect(display.sessionPercent == 42.0)
        #expect(display.rows[1].resetsAt == nil)
    }

    @Test func keepsUnknownLimitKindsInsteadOfDroppingThem() throws {
        let json = """
        {"limits": [{"kind": "weekly_scoped", "percent": 7, "resets_at": null,
                     "scope": {"model": {"display_name": "Opus 5"}}},
                    {"kind": "some_future_bucket", "percent": 3, "resets_at": null}]}
        """
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        let display = UsageDisplay(response)

        #expect(display.rows.map(\.title) == ["Weekly · Opus 5", "Some Future Bucket"])
    }

    @Test func unknownSeverityDegradesToNormal() throws {
        let json = """
        {"limits": [{"kind": "session", "percent": 5, "severity": "apocalyptic", "resets_at": null}]}
        """
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        #expect(response.limits.first?.severity == .normal)
    }
}
