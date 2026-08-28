import AppKit
import Observation

/// Re-rendering the label on every poll would be wasteful when the number has
/// not moved, so the image is keyed on what is actually visible: the rounded
/// percentage. A poll that shifts usage by 0.2% redraws nothing.
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
