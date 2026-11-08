import SwiftUI

enum Palette {
    static let accent = Color(hex: 0xD97757)
    static let warning = Color(hex: 0xC68A4B)
    static let critical = Color(hex: 0xBF4D28)
    static let lightBackground = Color(hex: 0xF0EEE6)
    static let darkBackground = Color(hex: 0x1F1E1D)

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
