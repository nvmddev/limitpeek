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
    }
}

extension UsageDisplay {
    init(_ response: UsageResponse, fetchedAt: Date = Date(), calendar: Calendar = .current) {
        self.fetchedAt = fetchedAt

        var rows: [Row] = []

        if !response.limits.isEmpty {
            rows = response.limits.enumerated().map { index, entry in
                // The array index is what keeps same-kind limits apart; the
                // model name only makes the ID readable. The kind stays first
                // so existing prefix checks keep working.
                let modelSuffix = (entry.scope?.model).map { ":\($0.displayName)" } ?? ""
                return Row(id: "\(entry.kind)#\(index)\(modelSuffix)",
                           kind: entry.kind,
                           title: Self.title(for: entry),
                           percent: entry.percent,
                           resetsAt: entry.resetsAt,
                           severity: entry.severity ?? .normal)
            }
        } else {
            let named: [(String, String, RateWindow?)] = [
                ("session", "5-hour limit", response.fiveHour),
                ("weekly_all", "Weekly · all models", response.sevenDay),
                ("weekly_opus", "Weekly · Opus", response.sevenDayOpus),
                ("weekly_sonnet", "Weekly · Sonnet", response.sevenDaySonnet)
            ]
            rows = named.compactMap { id, title, window in
                guard let window, let utilization = window.utilization else { return nil }
                return Row(id: id, kind: id, title: title,
                           percent: utilization, resetsAt: window.resetsAt)
            }
        }

        // `spend` over `extra_usage`: exact money with a currency.
        if let spend = response.spend, spend.enabled != false, let percent = spend.percent {
            rows.append(Row(id: "credits",
                            kind: "credits",
                            title: "Usage credits",
                            percent: percent,
                            resetsAt: Self.startOfNextMonth(after: fetchedAt, calendar: calendar),
                            severity: spend.severity ?? .normal,
                            detail: Self.creditsDetail(spend),
                            resetIsCalendarDate: true))
        }

        self.rows = rows
        self.sessionPercent = rows.first(where: { $0.kind == "session" })?.percent
            ?? response.fiveHour?.utilization
    }

    /// The one number every renderer uses: 0 for non-finite input, the 100.5
    /// sentinel for "over the limit" (the gauge clamps it to full), and a
    /// whole percentage otherwise. Rounding here rather than at each call site
    /// keeps the row, the menu bar label, and the cache from disagreeing.
    static func displayPercent(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        if percent > 100 { return 100.5 }
        return max(percent, 0).rounded()
    }

    /// Visual form for the menu bar and the popover row. The sentinel above
    /// reads "100%+"; negatives clamp to zero. Accessibility uses the spoken
    /// `percentDescription` instead.
    static func percentText(_ percent: Double) -> String {
        let display = displayPercent(percent)
        if display > 100 { return "100%+" }
        return "\(Int(display))%"
    }

    /// Spoken counterpart to `percentText`, keeping the existing
    /// "42 percent" phrasing.
    static func percentDescription(_ percent: Double) -> String {
        let display = displayPercent(percent)
        if display > 100 { return "over 100 percent" }
        return "\(Int(display)) percent"
    }

    private static func title(for entry: LimitEntry) -> String {
        if let model = entry.scope?.model?.displayName {
            return "Weekly · \(model)"
        }
        switch entry.kind {
        case "session": return "5-hour limit"
        case "weekly_all": return "Weekly · all models"
        case "weekly_opus": return "Weekly · Opus"
        case "weekly_sonnet": return "Weekly · Sonnet"
        default:
            // Humanise rather than drop, so an unknown kind still shows a row.
            return entry.kind
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func creditsDetail(_ spend: Spend) -> String? {
        guard let used = spend.used, let limit = spend.limit else { return nil }
        let code = used.currency ?? limit.currency ?? "USD"
        let usedText = used.amount.formatted(.currency(code: code))
        let limitText = limit.amount.formatted(.currency(code: code))
        return "\(usedText) of \(limitText)"
    }

    /// The API returns no reset date for credits; the official clients use
    /// midnight on the first of next month, local time.
    private static func startOfNextMonth(after date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let startOfThisMonth = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: startOfThisMonth)
    }
}
