import AppKit
import SwiftUI

/// A capsule gauge plus the percentage, rendered to one NSImage because
/// MenuBarExtra only reliably renders a Text or an Image. Below the warning
/// threshold it is a template image, tinted by macOS to match the menu bar.
enum MenuBarLabel {
    static let warningThreshold = 80.0
    static let criticalThreshold = 95.0

    /// Whole points throughout — a fractional edge on an image this small looks
    /// smeared. Change one and check the arithmetic still comes out even.
    private static let barWidth = 34.0
    private static let barHeight = 16.0
    private static let strokeWidth = 1.0
    private static let fillInset = 2.0
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

    @MainActor
    static func image(percent: Double?) -> NSImage {
        let tint = tint(for: percent)
        let content = Content(percent: percent, tint: tint)

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

    /// Nil means "render as a template and let macOS pick the colour".
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

    private struct Content: View {
        let percent: Double?
        let tint: Color?

        private var fraction: Double {
            min(max((percent ?? 0) / 100, 0), 1)
        }

        /// Template images are alpha-only, so black becomes the tint.
        private var foreground: Color { tint ?? .black }

        private var inset: Double { strokeWidth + fillInset }
        private var trackWidth: Double { barWidth - 2 * inset }
        private var fillHeight: Double { barHeight - 2 * inset }

        private var text: String {
            percent.map { "\(Int($0.rounded()))%" } ?? "—"
        }

        /// Rounded up, or every edge in the image lands on a half pixel.
        private var textWidth: Double {
            (text as NSString).size(withAttributes: [.font: textFont]).width.rounded(.up)
        }

        var body: some View {
            HStack(spacing: spacing) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .strokeBorder(foreground.opacity(0.6), lineWidth: strokeWidth)
                    if percent != nil {
                        Capsule()
                            .fill(foreground)
                            // Never narrower than a dot, so 1% still shows.
                            .frame(width: max((trackWidth * fraction).rounded(), fillHeight),
                                   height: fillHeight)
                            .padding(.leading, inset)
                    }
                }
                .frame(width: barWidth, height: barHeight)
                Text(text)
                    .font(Font(textFont))
                    .foregroundStyle(foreground)
                    .frame(width: textWidth, height: height, alignment: .leading)
            }
            .frame(height: height)
            .padding(.horizontal, 1)
        }
    }
}
