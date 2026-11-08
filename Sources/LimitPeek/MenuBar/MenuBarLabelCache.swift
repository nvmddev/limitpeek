import AppKit
import Observation

/// Keyed on what the drawing actually depends on, so a poll that moves usage
/// by 0.2% redraws nothing.
@MainActor
@Observable
final class MenuBarLabelCache {
    private struct Key: Equatable {
        /// Already quantised by `UsageDisplay.displayPercent`.
        var percent: Double?
        var style: MenuBarStyle
        /// A tinted label picks its own text colour instead of letting macOS
        /// tint a template image, so it has to be redrawn when the menu bar
        /// switches between light and dark.
        var isDark: Bool
    }

    private(set) var image = MenuBarLabel.image(percent: nil, style: .both, isDark: false)
    private var requestedKey: Key?
    private var renderedKey: Key?

    private var appearanceObservation: NSKeyValueObservation?

    init() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.redraw() }
        }
    }

    func update(percent: Double?, style: MenuBarStyle) {
        // Quantising first means a poll that moves usage by a fraction of a
        // percent redraws nothing.
        let key = Key(percent: percent.map(UsageDisplay.displayPercent),
                      style: style,
                      isDark: isDark)
        requestedKey = key
        render(key)
    }

    /// KVO fires before NSApp's own appearance update, so read it on the next
    /// main-actor turn.
    private func redraw() {
        guard let key = requestedKey else { return }
        render(Key(percent: key.percent,
                   style: key.style,
                   isDark: isDark))
    }

    private func render(_ key: Key) {
        requestedKey = key
        guard key != renderedKey else { return }
        renderedKey = key
        image = MenuBarLabel.image(percent: key.percent,
                                   style: key.style,
                                   isDark: key.isDark)
    }

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
