import Foundation
import Testing
@testable import LimitPeek

/// Row identity, the session-percent rule and the shared percentage formatter.
struct UsageDisplayTests {
    // MARK: - Row identity

    @Test func duplicateKindAndModelEntriesGetUniqueIDs() throws {
        let display = try display("""
        {"limits": [
            {"kind": "weekly_scoped", "percent": 10, "resets_at": null,
             "scope": {"model": {"display_name": "Opus"}}},
            {"kind": "weekly_scoped", "percent": 20, "resets_at": null,
             "scope": {"model": {"display_name": "Opus"}}}
        ]}
        """)

        #expect(display.rows.count == 2)
        #expect(display.rows.map(\.title) == ["Weekly · Opus", "Weekly · Opus"])
        #expect(display.rows[0].id != display.rows[1].id)
        #expect(Set(display.rows.map(\.id)).count == 2)
    }

    @Test func duplicateKindsWithoutAModelAlsoGetUniqueIDs() throws {
        let display = try display("""
        {"limits": [
            {"kind": "weekly_all", "percent": 10, "resets_at": null},
            {"kind": "weekly_all", "percent": 20, "resets_at": null}
        ]}
        """)

        #expect(display.rows.count == 2)
        #expect(Set(display.rows.map(\.id)).count == 2)
    }

    @Test func idsRemainStableAcrossDecodes() throws {
        let json = """
        {"limits": [{"kind": "session", "percent": 42, "resets_at": null}]}
        """
        let first = try display(json)
        let second = try display(json)

        #expect(first.rows.map(\.id) == second.rows.map(\.id))
    }

    // MARK: - Session percent

    @Test func sessionPercentUsesTheExactSessionKind() throws {
        let display = try display("""
        {"limits": [
            {"kind": "session_extra", "percent": 90, "resets_at": null},
            {"kind": "session", "percent": 30, "resets_at": null}
        ]}
        """)

        #expect(display.sessionPercent == 30)
    }

    @Test func prefixedKindIsNotTreatedAsSession() throws {
        let display = try display("""
        {"limits": [{"kind": "session_extra", "percent": 90, "resets_at": null}]}
        """)

        #expect(display.sessionPercent == nil)
    }

    @Test func prefixedKindFallsBackToTheNamedBucket() throws {
        let display = try display("""
        {"limits": [{"kind": "session_extra", "percent": 90, "resets_at": null}],
         "five_hour": {"utilization": 12}}
        """)

        #expect(display.sessionPercent == 12)
    }

    // MARK: - Percent text

    @Test func displayPercentQuantisesAndClamps() {
        #expect(UsageDisplay.displayPercent(79.6) == 80)
        #expect(UsageDisplay.displayPercent(150) == 100.5)
        #expect(UsageDisplay.displayPercent(-5) == 0)
        #expect(UsageDisplay.displayPercent(.nan) == 0)
        #expect(UsageDisplay.displayPercent(.infinity) == 0)
        #expect(UsageDisplay.displayPercent(-.infinity) == 0)
    }

    @Test func percentTextKeepsFullAndOverFullDistinct() {
        #expect(UsageDisplay.percentText(100.0) == "100%")
        #expect(UsageDisplay.percentText(100.1) == "100%+")
    }

    @Test func percentTextCoversTheDisplayRange() {
        #expect(UsageDisplay.percentText(0) == "0%")
        #expect(UsageDisplay.percentText(42) == "42%")
        #expect(UsageDisplay.percentText(99.4) == "99%")
        #expect(UsageDisplay.percentText(99.5) == "100%")
        #expect(UsageDisplay.percentText(100) == "100%")
        #expect(UsageDisplay.percentText(100.1) == "100%+")
    }

    @Test func percentTextClampsNegativeValues() {
        #expect(UsageDisplay.percentText(-0.1) == "0%")
        #expect(UsageDisplay.percentText(-42) == "0%")
    }

    @Test func percentTextDegradesNonFiniteValuesInsteadOfTrapping() {
        #expect(UsageDisplay.percentText(.infinity) == "0%")
        #expect(UsageDisplay.percentText(-.infinity) == "0%")
        #expect(UsageDisplay.percentText(.nan) == "0%")
    }

    @Test func percentDescriptionMatchesPercentText() {
        #expect(UsageDisplay.percentDescription(0) == "0 percent")
        #expect(UsageDisplay.percentDescription(42) == "42 percent")
        #expect(UsageDisplay.percentDescription(100) == "100 percent")
    }

    @Test func percentDescriptionUsesTheOverHundredPhrase() {
        #expect(UsageDisplay.percentText(100.1) == "100%+")
        #expect(UsageDisplay.percentDescription(100.1) == "over 100 percent")
    }

    @Test func percentDescriptionClampsAndDegradesLikePercentText() {
        #expect(UsageDisplay.percentDescription(-42) == "0 percent")
        #expect(UsageDisplay.percentDescription(.infinity) == "0 percent")
        #expect(UsageDisplay.percentDescription(-.infinity) == "0 percent")
        #expect(UsageDisplay.percentDescription(.nan) == "0 percent")
    }

    // MARK: - Menu bar / row consistency

    @Test func menuBarAccessibilityUsesTheRowFormat() {
        #expect(MenuBarLabel.accessibilityDescription(percent: 42)
                == "Claude usage: 42 percent of the 5-hour limit")
        #expect(MenuBarLabel.accessibilityDescription(percent: 42)
                .contains(UsageDisplay.percentDescription(42)))

        #expect(MenuBarLabel.accessibilityDescription(percent: 100.1)
                == "Claude usage: over 100 percent of the 5-hour limit")
        #expect(MenuBarLabel.accessibilityDescription(percent: 100.1)
                .contains(UsageDisplay.percentDescription(100.1)))

        #expect(MenuBarLabel.accessibilityDescription(percent: -5)
                == "Claude usage: 0 percent of the 5-hour limit")
    }

    @Test func zeroIsShownAsZeroEverywhere() {
        #expect(UsageDisplay.percentText(0) == "0%")
        #expect(UsageDisplay.percentDescription(0) == "0 percent")
        #expect(MenuBarLabel.accessibilityDescription(percent: 0)
                == "Claude usage: 0 percent of the 5-hour limit")
    }

    // MARK: - Helpers

    private func display(_ json: String) throws -> UsageDisplay {
        let response = try API.makeDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        return UsageDisplay(response, fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
