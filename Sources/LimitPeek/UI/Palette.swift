import SwiftUI

/// One palette for the whole app: neutral graphite at rest, so color only
/// appears as usage climbs, amber and then coral red. Controls take the accent
/// too instead of the system accent color, so a red or green system accent
/// cannot clash with the gauges. Dark mode gets lighter variants.
enum Palette {
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xC7CBD1) : Color(hex: 0x6D7279)
    }

    /// Text on an accent fill. Dark in dark mode, where the accent is too light
    /// for white.
    static func onAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1C1E22) : .white
    }

    /// Fixed colors rather than `.secondary`: vibrancy darkens a hierarchical
    /// style over whatever sits behind the glass, down to near black.
    static func glyph(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xC9CDD3) : Color(hex: 0x9298A1)
    }

    static func warning(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF3AF49) : Color(hex: 0xED9E2F)
    }

    static func critical(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xED6865) : Color(hex: 0xDB4144)
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
