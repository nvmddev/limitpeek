import SwiftUI

/// One usage limit: its title, when it resets, and a capacity bar with the
/// percentage right above it.
struct LimitRow: View {
    let row: UsageDisplay.Row

    var body: some View {
        let caption = details(spoken: false)
        VStack(alignment: .leading, spacing: 2) {
            if caption != nil {
                Text(row.title)
            }
            // The percentage sits on whichever line is closest to the bar.
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let caption {
                    Text(caption)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.title)
                }
                Spacer(minLength: 8)
                Text(UsageDisplay.percentText(row.percent))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            // The sentinel for "over the limit" fills the bar.
            Gauge(value: min(UsageDisplay.displayPercent(row.percent), 100), in: 0...100) {
                Text(row.title)
            }
            .gaugeStyle(CapacityBarStyle())
            .tint(Palette.color(for: row.level))
            .padding(.top, 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, UsageDisplay.percentDescription(row.percent), details(spoken: true)]
            .compactMap { $0 }
            .joined(separator: ", "))
    }

    /// "$3.00 of $15.00 · resets Dec 1", or either half alone.
    private func details(spoken: Bool) -> String? {
        let reset = ResetFormatter.string(for: row, spoken: spoken).map { "resets \($0)" }
        let parts = [row.detail, reset].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: spoken ? ", " : " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
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

/// When a limit resets: the clock time and what is left within a day, the
/// weekday and time within a week, and the date beyond that or for credits,
/// which reset on a calendar boundary.
enum ResetFormatter {
    static func string(for row: UsageDisplay.Row,
                       now: Date = .now,
                       spoken: Bool = false,
                       locale: Locale = .autoupdatingCurrent) -> String? {
        guard let resetsAt = row.resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        if row.resetIsCalendarDate || remaining > 7 * 86_400 {
            return resetsAt.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        }
        if remaining > 86_400 {
            return resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
        }
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        // Rounded up, so the clock in the menu bar plus this lands on `time`.
        let left = Duration.seconds(remaining).formatted(
            .units(allowed: [.hours, .minutes],
                   width: spoken ? .wide : .narrow,
                   fractionalPart: .hide(rounded: .up))
            .locale(locale))
        return spoken ? "at \(time), in \(left)" : "at \(time) (\(left))"
    }
}
