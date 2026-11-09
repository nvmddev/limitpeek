import Foundation

/// What the UI renders: an ordered list of rows plus the number that goes in
/// the menu bar. Separate from `UsageResponse` so the wire format can change
/// without touching a view.
struct UsageDisplay: Sendable, Equatable {
    var rows: [Row] = []
    /// Nil when the account reports no session window.
    var sessionPercent: Double?
    var fetchedAt: Date

    struct Row: Identifiable, Sendable, Equatable {
        var id: String
        /// Wire `kind`, kept explicitly so callers never have to parse `id`.
        var kind: String
        var title: String
        /// Usually 0–100; above that it is displayed as "100%+".
        var percent: Double
        var resetsAt: Date?
        var severity: Severity = .normal
        /// Secondary line, e.g. "$3.00 of $15.00".
        var detail: String?
        /// Credits reset on a calendar boundary, so a date rather than a countdown.
        var resetIsCalendarDate: Bool = false

        /// The percentage decides once it crosses a threshold; below that the
        /// server's own severity can still raise it.
        var level: Severity {
            let level = Severity(percent: percent)
            return level == .normal ? severity : level
        }
    }
}

extension UsageDisplay {
    init(_ response: UsageResponse, fetchedAt: Date = .now, calendar: Calendar = .current) {
        self.fetchedAt = fetchedAt

        var rows: [Row]
        if !response.limits.isEmpty {
            rows = response.limits.enumerated().map { index, entry in
                // The array index keeps same-kind limits apart; the model name
                // only makes the ID readable.
                let model = entry.scope?.model?.displayName
                return Row(id: "\(entry.kind)#\(index)" + (model.map { ":\($0)" } ?? ""),
                           kind: entry.kind,
                           title: model.map { "Weekly · \($0)" } ?? Self.title(forKind: entry.kind),
                           percent: entry.percent,
                           resetsAt: entry.resetsAt,
                           severity: entry.severity ?? .normal)
            }
        } else {
            let named: [(kind: String, window: RateWindow?)] = [
                ("session", response.fiveHour),
                ("weekly_all", response.sevenDay),
                ("weekly_opus", response.sevenDayOpus),
                ("weekly_sonnet", response.sevenDaySonnet)
            ]
            rows = named.compactMap { kind, window in
                guard let window, let utilization = window.utilization else { return nil }
                return Row(id: kind, kind: kind, title: Self.title(forKind: kind),
                           percent: utilization, resetsAt: window.resetsAt)
            }
        }

        // `spend` over `extra_usage`: exact money with a currency.
        if let spend = response.spend, spend.enabled != false, let percent = spend.percent {
            rows.append(Row(id: "credits",
                            kind: "credits",
                            title: "Usage credits",
                            percent: percent,
                            // The API returns no reset date for credits; the
                            // official clients use the first of next month.
                            resetsAt: calendar.dateInterval(of: .month, for: fetchedAt)?.end,
                            severity: spend.severity ?? .normal,
                            detail: Self.creditsDetail(spend),
                            resetIsCalendarDate: true))
        }

        self.rows = rows
        self.sessionPercent = rows.first { $0.kind == "session" }?.percent
            ?? response.fiveHour?.utilization
    }

    /// The one number every renderer uses: 0 for non-finite input, the 100.5
    /// sentinel for "over the limit" (the gauge clamps it to full), and a
    /// whole percentage otherwise. Rounding here rather than at each call site
    /// keeps the row, the menu bar label and its image key from disagreeing.
    static func displayPercent(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        if percent > 100 { return 100.5 }
        return max(percent, 0).rounded()
    }

    /// Visual form for the menu bar and the menu rows. The sentinel above
    /// reads "100%+"; negatives clamp to zero.
    static func percentText(_ percent: Double) -> String {
        let display = displayPercent(percent)
        return display > 100 ? "100%+" : "\(Int(display))%"
    }

    /// Spoken counterpart to `percentText`.
    static func percentDescription(_ percent: Double) -> String {
        let display = displayPercent(percent)
        return display > 100 ? "over 100 percent" : "\(Int(display)) percent"
    }

    private static func title(forKind kind: String) -> String {
        switch kind {
        case "session": "5-hour limit"
        case "weekly_all": "Weekly · all models"
        case "weekly_opus": "Weekly · Opus"
        case "weekly_sonnet": "Weekly · Sonnet"
        // Humanise rather than drop, so an unknown kind still shows a row.
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func creditsDetail(_ spend: Spend) -> String? {
        guard let used = spend.used, let limit = spend.limit else { return nil }
        let currency = Decimal.FormatStyle.Currency(code: used.currency ?? limit.currency ?? "USD")
        return "\(used.amount.formatted(currency)) of \(limit.amount.formatted(currency))"
    }
}

extension Severity {
    /// Amber from 80%, red from 95%, judged on the rounded value the text
    /// shows, so 79.6% reads and colors as 80% everywhere.
    init(percent: Double) {
        let shown = UsageDisplay.displayPercent(percent)
        self = shown >= 95 ? .critical : shown >= 80 ? .warning : .normal
    }
}
