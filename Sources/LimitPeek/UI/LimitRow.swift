import SwiftUI

/// One usage limit: title, percentage, reset time, and a bar.
struct LimitRow: View {
    let row: UsageDisplay.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 13))
                    if let detail = row.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(trailingText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            GaugeBar(fraction: min(row.percent, 100) / 100, tint: tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(Int(row.percent.rounded())) percent used")
    }

    private var trailingText: String {
        let percent = "\(Int(row.percent.rounded()))%"
        guard let reset = ResetFormatter.string(for: row) else { return percent }
        return "\(percent) · resets \(reset)"
    }

    private var tint: Color {
        if row.percent >= MenuBarLabel.criticalThreshold { return .red }
        if row.percent >= MenuBarLabel.warningThreshold { return .orange }
        return switch row.severity {
        case .critical: .red
        case .warning: .orange
        case .normal: .accentColor
        }
    }
}

/// A plain capsule gauge — ProgressView won't hold this height and radius.
struct GaugeBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint)
                    // A sliver at 1%, not a dot.
                    .frame(width: fraction > 0 ? max(geometry.size.width * fraction, 3) : 0)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }
}

enum ResetFormatter {
    /// A countdown inside a week, a date beyond that or for credits.
    static func string(for row: UsageDisplay.Row, now: Date = Date()) -> String? {
        guard let resetsAt = row.resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return nil }

        if row.resetIsCalendarDate || interval > 7 * 24 * 3600 {
            return resetsAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return resetsAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
