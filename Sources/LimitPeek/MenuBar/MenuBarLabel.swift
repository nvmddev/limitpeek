import AppKit
import SwiftUI

/// A small gauge plus the percentage, drawn into one image because a status
/// item shows an image and nothing richer. The drawing handler runs when the
/// status item draws, so it sees the menu bar's own appearance, which follows
/// the desktop picture rather than the system setting. Below the warning
/// threshold the image is a template, tinted by macOS; above it the gauge
/// carries its own color and the rest is drawn in the menu bar's foreground,
/// which a template image cannot express.
enum MenuBarLabel {
    /// Everything the drawing depends on, quantised like the text, so equal
    /// keys draw the same image.
    struct Key: Equatable, Sendable {
        let percent: Double?
        let style: MenuBarStyle
        let isSignedIn: Bool

        init(percent: Double?, style: MenuBarStyle, isSignedIn: Bool) {
            self.percent = percent.map(UsageDisplay.displayPercent)
            self.style = style
            self.isSignedIn = isSignedIn
        }
    }

    /// Shaped like the system battery indicator. Whole points only, or the
    /// edges land on half a pixel and smear.
    private static let barSize = CGSize(width: 26, height: 12)
    private static let fillInset = 2.0
    private static let minFillWidth = 2.0
    /// Concentric with the outline, so the gap stays even in the corners.
    private static let barCornerRadius = 3.5
    private static let spacing = 5.0
    private static let height = 16.0
    private static let padding = 1.0

    static func image(for key: Key) -> NSImage {
        let tint: NSColor? = switch key.percent.map(Severity.init(percent:)) ?? .normal {
        case .normal: nil
        case .warning: Palette.warningColor
        case .critical: Palette.criticalColor
        }
        let text = key.percent.map(UsageDisplay.percentText) ?? "—"
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                    weight: .regular)
        // Rounded up, or every edge after the text lands on a half pixel.
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        let style = key.style
        let width = 2 * padding
            + (style.showsBar ? barSize.width : 0)
            + (style.showsBar && style.showsPercentage ? spacing : 0)
            + (style.showsPercentage ? textWidth : 0)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Template images are alpha-only, so black stands in for whatever
            // macOS tints them with.
            let foreground = tint == nil ? NSColor.black : menuBarForeground()
            let gauge = tint ?? foreground
            var x = padding
            if style.showsBar {
                drawBar(at: x, percent: key.percent, color: gauge)
                x += barSize.width + spacing
            }
            if style.showsPercentage {
                // Without the gauge the number is the only thing left to
                // carry the warning color.
                let color = style.showsBar ? foreground : gauge
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (text as NSString).size(withAttributes: attributes)
                (text as NSString).draw(at: CGPoint(x: x, y: (height - size.height) / 2),
                                        withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = accessibilityDescription(percent: key.percent,
                                                                  isSignedIn: key.isSignedIn)
        return image
    }

    /// The status item reads this, not a SwiftUI label.
    static func accessibilityDescription(percent: Double?, isSignedIn: Bool = true) -> String {
        guard isSignedIn else { return "Claude usage: not signed in" }
        guard let percent else { return "Claude usage: no data" }
        return "Claude usage: \(UsageDisplay.percentDescription(percent)) of the 5-hour limit"
    }

    /// What macOS tints a template image with in the appearance being drawn.
    private static func menuBarForeground() -> NSColor {
        NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }

    private static func drawBar(at x: Double, percent: Double?, color: NSColor) {
        let bar = CGRect(x: x, y: (height - barSize.height) / 2,
                         width: barSize.width, height: barSize.height)
        let outline = roundedRect(bar.insetBy(dx: 0.5, dy: 0.5), radius: barCornerRadius - 0.5)
        outline.lineWidth = 1
        color.withAlphaComponent(0.5).setStroke()
        outline.stroke()

        // The same quantisation as the text; the over-limit sentinel fills it.
        let fraction = min((percent ?? 0) / 100, 1)
        guard fraction > 0 else { return }
        let track = bar.insetBy(dx: fillInset, dy: fillInset)
        // A sliver at 1%, never a dot wide enough to look like a switch.
        let fill = CGRect(x: track.minX, y: track.minY,
                          width: max((track.width * fraction).rounded(), minFillWidth),
                          height: track.height)
        color.setFill()
        roundedRect(fill, radius: barCornerRadius - fillInset).fill()
    }

    private static func roundedRect(_ rect: CGRect, radius: Double) -> NSBezierPath {
        NSBezierPath(cgPath: Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath)
    }
}
