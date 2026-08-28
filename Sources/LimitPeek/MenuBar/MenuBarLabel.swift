import AppKit
import SwiftUI

/// A small gauge plus the percentage, rendered to one NSImage because
/// MenuBarExtra only reliably renders a Text or an Image. Below the warning
/// threshold it is a template image, tinted by macOS to match the menu bar;
/// above it the gauge carries its own colour and the rest is drawn in the
/// menu bar's own foreground, which a template image cannot express.
enum MenuBarLabel {
    static let warningThreshold = 80.0
    static let criticalThreshold = 95.0

    /// Shaped like the system battery indicator. Whole points only, or the
    /// edges land on half a pixel and smear.
    private static let barWidth = 26.0
    private static let barHeight = 12.0
    private static let strokeWidth = 1.0
    private static let fillInset = 2.0
    private static let minFillWidth = 2.0
    /// Concentric with the outline, so the gap stays even in the corners.
    private static let barCornerRadius = 3.5
    private static let fillCornerRadius = barCornerRadius - fillInset
    private static let outlineOpacity = 0.5
    private static let spacing = 5.0
    private static let height = 16.0

    private static var textFont: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }

    /// One rep per density rather than one for "the" screen: NSScreen.main
    /// follows keyboard focus, not the menu bar.
    private static var scales: [Double] {
        Set([1.0, 2.0] + NSScreen.screens.map { Double($0.backingScaleFactor) }).sorted()
    }

    /// What macOS would tint a template image with, for the colour the
    /// tinted label has to match by hand.
    @MainActor
    static var menuBarForeground: Color {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .white : .black
    }

    @MainActor
    static func image(percent: Double?, style: MenuBarStyle) -> NSImage {
        let tint = tint(for: percent)
        // Template images are alpha-only, so black stands in for whatever
        // macOS tints them with.
        let content = Content(percent: percent,
                              style: style,
                              tint: tint,
                              foreground: tint == nil ? .black : menuBarForeground)

        let image = NSImage()
        var pointSize: NSSize?
        for scale in scales {
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            guard let rendered = renderer.cgImage else { continue }
            // Without an explicit point size AppKit reads the pixel count as
            // points and the 2x rep draws at double size.
            let size = NSSize(width: Double(rendered.width) / scale,
                              height: Double(rendered.height) / scale)
            let rep = NSBitmapImageRep(cgImage: rendered)
            rep.size = size
            image.addRepresentation(rep)
            pointSize = size
        }
        guard let pointSize else { return NSImage() }

        image.size = pointSize
        image.isTemplate = (tint == nil)
        image.accessibilityDescription = accessibilityDescription(percent: percent)
        return image
    }

    /// Nil means "template image, macOS picks the colour".
    private static func tint(for percent: Double?) -> Color? {
        guard let percent else { return nil }
        if percent >= criticalThreshold { return .red }
        if percent >= warningThreshold { return .orange }
        return nil
    }

    static func accessibilityDescription(percent: Double?) -> String {
        guard let percent else { return "Claude usage: not signed in" }
        return "Claude usage: \(Int(percent.rounded())) percent of the 5-hour limit"
    }

    /// Not private: `scripts/ReadmeArt.swift` draws it at its own scale and
    /// colour for the README.
    struct Content: View {
        let percent: Double?
        var style = MenuBarStyle.both
        /// Colour of the gauge alone; nil leaves it in `foreground`.
        let tint: Color?
        /// Everything the gauge does not colour: the percentage, and the
        /// gauge itself while it is untinted.
        var foreground: Color = .black

        private var fraction: Double {
            min(max((percent ?? 0) / 100, 0), 1)
        }

        private var gauge: Color { tint ?? foreground }

        /// Without the gauge the number is the only thing left to carry the
        /// warning colour.
        private var textColor: Color { style.showsBar ? foreground : gauge }

        private var trackWidth: Double { barWidth - 2 * fillInset }
        private var fillHeight: Double { barHeight - 2 * fillInset }

        /// A sliver at 1%, never a dot wide enough to look like a switch.
        private var fillWidth: Double {
            guard percent != nil, fraction > 0 else { return 0 }
            return max((trackWidth * fraction).rounded(), minFillWidth)
        }

        private var text: String {
            percent.map { "\(Int($0.rounded()))%" } ?? "—"
        }

        /// Rounded up, or every edge in the image lands on a half pixel.
        private var textWidth: Double {
            (text as NSString).size(withAttributes: [.font: textFont]).width.rounded(.up)
        }

        var body: some View {
            HStack(spacing: spacing) {
                if style.showsBar {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                            .strokeBorder(gauge.opacity(outlineOpacity),
                                          lineWidth: strokeWidth)
                        RoundedRectangle(cornerRadius: fillCornerRadius, style: .continuous)
                            .fill(gauge)
                            .frame(width: fillWidth, height: fillHeight)
                            .padding(.leading, fillInset)
                    }
                    .frame(width: barWidth, height: barHeight)
                }
                if style.showsPercentage {
                    Text(text)
                        .font(Font(textFont))
                        .foregroundStyle(textColor)
                        .frame(width: textWidth, height: height, alignment: .leading)
                }
            }
            .frame(height: height)
            .padding(.horizontal, 1)
        }
    }
}
