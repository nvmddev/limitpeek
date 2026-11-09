import AppKit
import Testing
@testable import LimitPeek

/// Keys decide when the status item gets a new image, so they must ignore
/// what the drawing ignores. The drawing itself is checked offscreen, in the
/// appearances the menu bar hands it.
@MainActor
struct MenuBarLabelTests {
    // MARK: - Keys

    @Test func keysQuantiseLikeTheText() {
        #expect(key(42) == key(42.2))
        #expect(key(41.4) == key(40.8))
        #expect(key(41.6) != key(40.8))
        #expect(key(-10) == key(0.4))
    }

    @Test func everythingAboveOneHundredSharesOneKey() {
        #expect(key(100.1) == key(100.4))
        #expect(key(100.1) == key(250))
        #expect(key(100) != key(100.1))
    }

    @Test func nonFiniteValuesCountAsZeroAndNoDataStaysDistinct() {
        #expect(key(.infinity) == key(0))
        #expect(key(-.infinity) == key(0))
        #expect(key(.nan) == key(0))
        #expect(key(nil) != key(0))
    }

    @Test func keysTellStylesAndSignInApart() {
        #expect(key(42, style: .both) != key(42, style: .bar))
        #expect(key(42, style: .bar) != key(42, style: .percentage))
        #expect(key(nil, isSignedIn: true) != key(nil, isSignedIn: false))
    }

    // MARK: - Image

    @Test func staysATemplateBelowTheWarningThreshold() {
        #expect(image(nil).isTemplate)
        #expect(image(79.4).isTemplate)
        #expect(!image(79.6).isTemplate)
        #expect(!image(97).isTemplate)
    }

    @Test func sizeFollowsTheStyle() {
        let bar = image(42, style: .bar).size
        let percentage = image(42, style: .percentage).size
        let both = image(42, style: .both).size

        #expect(bar == NSSize(width: 28, height: 16))
        #expect(both.width == bar.width + percentage.width - 2 + 5)
        #expect(both.height == 16)
    }

    @Test func describesItselfForVoiceOver() {
        #expect(image(42).accessibilityDescription == "Claude usage: 42 percent of the 5-hour limit")
        #expect(image(nil).accessibilityDescription == "Claude usage: no data")
        #expect(image(nil, isSignedIn: false).accessibilityDescription == "Claude usage: not signed in")
    }

    @Test func tintedTextFollowsTheMenuBarsOwnAppearance() {
        let label = image(90)

        #expect(textBrightness(of: label, in: .vibrantDark) > 0.9)
        #expect(textBrightness(of: label, in: .darkAqua) > 0.9)
        #expect(textBrightness(of: label, in: .vibrantLight) < 0.1)
        #expect(textBrightness(of: label, in: .aqua) < 0.1)
    }

    // MARK: - Helpers

    private func key(_ percent: Double?, style: MenuBarStyle = .both, isSignedIn: Bool = true) -> MenuBarLabel.Key {
        MenuBarLabel.Key(percent: percent, style: style, isSignedIn: isSignedIn)
    }

    private func image(_ percent: Double?, style: MenuBarStyle = .both, isSignedIn: Bool = true) -> NSImage {
        MenuBarLabel.image(for: key(percent, style: style, isSignedIn: isSignedIn))
    }

    /// Brightness of the most opaque pixel right of the gauge, where the
    /// percentage is drawn.
    private func textBrightness(of image: NSImage, in appearance: NSAppearance.Name) -> Double {
        let scale = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(image.size.width) * scale,
                                   pixelsHigh: Int(image.size.height) * scale,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: image.size))
        }
        NSGraphicsContext.restoreGraphicsState()

        var best = (alpha: 0.0, brightness: 0.0)
        for y in 0..<rep.pixelsHigh {
            for x in (32 * scale)..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > best.alpha {
                    best = (color.alphaComponent, color.brightnessComponent)
                }
            }
        }
        return best.brightness
    }
}
