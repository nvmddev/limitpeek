import SwiftUI

enum Palette {
    static let accent = Color(hex: 0xD97757)
    static let lightBackground = Color(hex: 0xF0EEE6)
    static let darkBackground = Color(hex: 0x1F1E1D)

    /// Fill for the selected menu-bar segment. White on this measures 4.99:1
    /// (WCAG AA needs 4.5:1), versus only 3.12:1 on `accent`. Independent of
    /// the color scheme because the comparison is against the white text.
    static let selectionFill = Color(hex: 0xB4532A)

    /// Darker in light mode so the warning gauge and text keep enough contrast.
    static func warning(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xC68A4B) : Color(hex: 0x9C5A1B)
    }

    static func critical(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE8835E) : Color(hex: 0xB14A24)
    }

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : lightBackground
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
