import AppKit
import Observation

/// Keyed on the rounded percentage, so a poll that moves usage by 0.2%
/// redraws nothing.
@MainActor
@Observable
final class MenuBarLabelCache {
    private(set) var image: NSImage = MenuBarLabel.image(percent: nil)
    private var renderedKey: Int?

    func update(percent: Double?) {
        let key = percent.map { Int($0.rounded()) }
        guard key != renderedKey else { return }
        renderedKey = key
        image = MenuBarLabel.image(percent: percent)
    }
}
