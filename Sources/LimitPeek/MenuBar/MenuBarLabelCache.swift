import AppKit
import Observation

/// Keyed on what the drawing actually depends on, so a poll that moves usage
/// by 0.2% redraws nothing.
@MainActor
@Observable
final class MenuBarLabelCache {
    private struct Key: Equatable {
        var percent: Int?
        var style: MenuBarStyle
        /// A tinted label picks its own text colour instead of letting macOS
        /// tint a template image, so it has to be redrawn when the menu bar
        /// switches between light and dark.
        var isDark: Bool
    }

    private(set) var image = MenuBarLabel.image(percent: nil, style: .both)
    private var renderedKey: Key?

    /// The observer outlives the cache, which lives as long as the app; it
    /// holds self weakly, so an orphaned registration is a no-op.
    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    func update(percent: Double?, style: MenuBarStyle) {
        render(Key(percent: percent.map { Int($0.rounded()) },
                   style: style,
                   isDark: isDark))
    }

    /// The notification beats NSApp's own appearance update, so read it on the
    /// next turn of the run loop.
    private func redraw() {
        guard let key = renderedKey else { return }
        Task { @MainActor in
            self.render(Key(percent: key.percent,
                            style: key.style,
                            isDark: self.isDark))
        }
    }

    private func render(_ key: Key) {
        guard key != renderedKey else { return }
        renderedKey = key
        image = MenuBarLabel.image(percent: key.percent.map(Double.init),
                                   style: key.style)
    }

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
