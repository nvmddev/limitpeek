import AppKit
import SwiftUI

/// One palette for the whole app: neutral graphite at rest, so color only
/// appears as usage climbs, amber and then coral red. Every color resolves
/// against the appearance it is drawn in, with lighter variants for dark mode.
enum Palette {
    static let accent = Color(nsColor: NSColor(light: 0x6D7279, dark: 0xC7CBD1))
    /// Fixed colors rather than `.secondary`, which vibrancy darkens over
    /// whatever sits behind the menu.
    static let glyph = Color(nsColor: NSColor(light: 0x9298A1, dark: 0xC9CDD3))
    static let warning = Color(nsColor: warningColor)
    static let critical = Color(nsColor: criticalColor)

    /// The menu bar label is drawn by AppKit, outside SwiftUI.
    static let warningColor = NSColor(light: 0xED9E2F, dark: 0xF3AF49)
    static let criticalColor = NSColor(light: 0xDB4144, dark: 0xED6865)

    static func color(for level: Severity) -> Color {
        switch level {
        case .normal: accent
        case .warning: warning
        case .critical: critical
        }
    }
}

private extension NSColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    convenience init(hex: UInt32) {
        self.init(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
