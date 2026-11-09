import SwiftUI

struct LimitRow: View {
    let row: UsageDisplay.Row
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                Spacer(minLength: 8)
                Text(trailingText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Gauge(value: min(shownPercent, 100), in: 0...100) {
                Text(row.title)
            }
            .gaugeStyle(CapacityBarStyle())
            .tint(tint)
            .padding(.top, 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, spokenTrailingText, row.detail]
            .compactMap { $0 }
            .joined(separator: ", "))
    }

    /// One number for the gauge, the colour, and the visible text, so the row
    /// cannot disagree with the menu bar about rounding or thresholds.
    private var shownPercent: Double {
        UsageDisplay.displayPercent(row.percent)
    }

    private var trailingText: String {
        let percent = UsageDisplay.percentText(shownPercent)
        guard let reset = ResetFormatter.string(for: row) else { return percent }
        return "\(percent) · resets \(reset)"
    }

    /// The visual "100%+" is not useful spoken aloud; describe the real value.
    private var spokenTrailingText: String {
        let percent = UsageDisplay.percentDescription(row.percent)
        guard let reset = ResetFormatter.string(for: row) else { return percent }
        return "\(percent), resets \(reset)"
    }

    private var tint: Color {
        if shownPercent >= MenuBarLabel.criticalThreshold { return Palette.critical(for: colorScheme) }
        if shownPercent >= MenuBarLabel.warningThreshold { return Palette.warning(for: colorScheme) }
        return switch row.severity {
        case .critical: Palette.critical(for: colorScheme)
        case .warning: Palette.warning(for: colorScheme)
        case .normal: Palette.accent(for: colorScheme)
        }
    }
}

/// A slim bar on a track of its own tint, so a row reads as one color rather
/// than a color on gray. Zero draws no fill at all, unlike the system style's dot.
struct CapacityBarStyle: GaugeStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(.tint.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    if configuration.value > 0 {
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(proxy.size.width * configuration.value,
                                              proxy.size.height))
                    }
                }
            }
            .frame(height: 6)
    }
}

enum ResetFormatter {
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
