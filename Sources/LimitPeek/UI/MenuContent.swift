import SwiftUI

/// The app glyph beside a bold title and a secondary line, at the top of the
/// menu and the sign-in window, with the app version in the menu's corner.
struct MenuHeader: View {
    let title: String
    var subtitle: String?
    var version: String?

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph()
                .fill(Palette.glyph)
                .frame(width: 26, height: 26 / AppGlyph.aspectRatio)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                    if let version {
                        Spacer(minLength: 0)
                        Text("v\(version)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .accessibilityLabel("Version \(version)")
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An error or notice, wrapped to the menu's width.
struct MenuNote: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
