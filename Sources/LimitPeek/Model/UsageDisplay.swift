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
        var title: String
        /// 0–100.
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

        // `limits` is ordered, carries severity, and gains new kinds on its own.
        if !response.limits.isEmpty {
            rows = response.limits.map { entry in
                Row(id: entry.kind + (entry.scope?.model?.displayName ?? ""),
                    title: Self.title(for: entry),
                    percent: entry.percent,
                    resetsAt: entry.resetsAt,
                    severity: entry.severity ?? .normal)
            }
        } else {
            // For responses where `limits` is absent.
            let named: [(String, String, RateWindow?)] = [
                ("session", "5-hour limit", response.fiveHour),
                ("weekly_all", "Weekly · all models", response.sevenDay),
                ("weekly_opus", "Weekly · Opus", response.sevenDayOpus),
                ("weekly_sonnet", "Weekly · Sonnet", response.sevenDaySonnet)
            ]
            rows = named.compactMap { id, title, window in
                guard let window, let utilization = window.utilization else { return nil }
                return Row(id: id, title: title, percent: utilization, resetsAt: window.resetsAt)
            }
        }

        // `spend` over `extra_usage`: exact minor-unit money with a currency.
        if let spend = response.spend, spend.enabled != false, let percent = spend.percent {
            rows.append(Row(id: "credits",
                            title: "Usage credits",
                            percent: percent,
                            resetsAt: Self.startOfNextMonth(after: fetchedAt, calendar: calendar),
                            severity: spend.severity ?? .normal,
                            detail: Self.creditsDetail(spend),
                            resetIsCalendarDate: true))
        }

        self.rows = rows
        self.sessionPercent = rows.first(where: { $0.id.hasPrefix("session") })?.percent
            ?? response.fiveHour?.utilization
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
