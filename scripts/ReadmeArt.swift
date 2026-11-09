// Draws the README pictures with the app's own views, so they cannot drift
// from what ships.
//
//   scripts/make-readme-art.sh

import AppKit
import SwiftUI

/// The README shows the pictures at a third of their pixel size, so they stay
/// sharp on a Retina display.
let scale = 3.0
let outputDirectory = URL(fileURLWithPath: "docs", isDirectory: true)

let fixtureAccount = Account(id: "00000000-0000-0000-0000-000000000000",
                             displayName: "Alex Rivera",
                             organizationName: "Acme Corp")

/// Built from the response the tests pin, so the popover shows buckets the API
/// really returns. Every date the API supplied moves by the same amount, which
/// puts the 5-hour reset three hours out and leaves the weekly one where the
/// API had it relative to that.
@MainActor
func fixtureDisplay(now: Date = Date()) -> UsageDisplay {
    let json = try! Data(contentsOf: URL(fileURLWithPath: "Tests/LimitPeekTests/Fixtures/usage.json"))
    let response = try! API.makeDecoder().decode(UsageResponse.self, from: json)
    var display = UsageDisplay(response, fetchedAt: now)

    guard let session = display.rows.first(where: { $0.id.hasPrefix("session") })?.resetsAt else {
        return display
    }
    let shift = now.addingTimeInterval(3 * 3600).timeIntervalSince(session)
    display.rows = display.rows.map { row in
        guard !row.resetIsCalendarDate else { return row }
        var row = row
        row.resetsAt = row.resetsAt?.addingTimeInterval(shift)
        return row
    }
    return display
}

enum Appearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    /// What the menu bar tints a template image with.
    var menuBarForeground: Color { self == .dark ? .white : .black }
    /// What sits behind the panel. Plain and neutral, so the translucent
    /// material looks the same on every machine instead of picking up the
    /// desktop.
    var backdrop: NSColor { self == .dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.9, alpha: 1) }
}

struct MenuBarStrip: View {
    let appearance: Appearance

    var body: some View {
        HStack(spacing: 24) {
            MenuBarLabel.Content(percent: 40, tint: nil,
                                 foreground: appearance.menuBarForeground)
            MenuBarLabel.Content(percent: 84, tint: Palette.warning(for: appearance.colorScheme),
                                 foreground: appearance.menuBarForeground)
            MenuBarLabel.Content(percent: 97, tint: Palette.critical(for: appearance.colorScheme),
                                 foreground: appearance.menuBarForeground)
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The popover is shot on screen with `screencapture`, because NSHostingView
/// only draws the AppKit-backed controls (the switch) and the window material
/// in a live, key window. That needs Screen Recording
/// permission for the terminal running the script. The capture comes out at
/// the main display's scale, with the window shadow.
@MainActor
func shootPopover(store: AccountStore, appearance: Appearance) {
    let hosting = NSHostingView(rootView: UsagePopover(refresher: Refresher()).environment(store))
    let size = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: size)

    // The material macOS draws behind menus, which is what the menu bar
    // extra's window shows. An NSGlassEffectView in a borderless panel renders
    // a flat, dimmed gray instead.
    let material = NSVisualEffectView(frame: hosting.frame)
    material.material = .menu
    material.state = .active
    material.blendingMode = .behindWindow
    material.maskImage = NSImage(size: NSSize(width: 33, height: 33), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
        return true
    }
    material.maskImage?.capInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    material.maskImage?.resizingMode = .stretch
    material.addSubview(hosting)

    let visible = NSScreen.main!.visibleFrame
    let frame = NSRect(x: visible.midX - size.width / 2,
                       y: visible.midY - size.height / 2,
                       width: size.width,
                       height: size.height)

    let backdrop = NSWindow(contentRect: frame.insetBy(dx: -80, dy: -80),
                            styleMask: .borderless,
                            backing: .buffered,
                            defer: false)
    backdrop.backgroundColor = appearance.backdrop
    backdrop.level = .popUpMenu
    backdrop.orderFrontRegardless()

    let panel = KeyPanel(contentRect: frame,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 1)
    panel.appearance = appearance.nsAppearance
    panel.contentView = material
    panel.makeKeyAndOrderFront(nil)

    // Long enough for the window server to composite the material; the
    // shadow is then recomputed from the rounded content, not the frame.
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    panel.invalidateShadow()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))

    let url = outputDirectory.appendingPathComponent("popover-\(appearance.rawValue).png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-l\(panel.windowNumber)", url.path]
    do {
        try capture.run()
    } catch {
        fatalError("could not run screencapture: \(error)")
    }
    capture.waitUntilExit()
    guard capture.terminationStatus == 0 else {
        fatalError("screencapture failed; grant the terminal Screen Recording permission")
    }

    panel.orderOut(nil)
    backdrop.orderOut(nil)
    let pixels = NSImageRep(contentsOf: url).map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? "?"
    print("  \(url.path) (\(pixels))")
}

@MainActor
func write(_ view: some View, appearance: Appearance, to name: String) {
    let hosting = NSHostingView(rootView: view.environment(\.colorScheme, appearance.colorScheme))
    hosting.appearance = appearance.nsAppearance
    let size = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.layoutSubtreeIfNeeded()

    let pixelsWide = Int((size.width * scale).rounded())
    let pixelsHigh = Int((size.height * scale).rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelsWide,
                                     pixelsHigh: pixelsHigh,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create a bitmap context for \(name)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    appearance.nsAppearance.performAsCurrentDrawingAppearance {
        hosting.displayIgnoringOpacity(hosting.bounds, in: context)
    }
    NSGraphicsContext.restoreGraphicsState()

    let url = outputDirectory.appendingPathComponent("\(name)-\(appearance.rawValue).png")
    // Re-encode through an sRGB context so the PNG carries an sRGB tag;
    // untagged deviceRGB shifts the colors in some viewers.
    guard let image = rep.cgImage,
          let srgb = CGContext(data: nil,
                               width: image.width,
                               height: image.height,
                               bitsPerComponent: 8,
                               bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                             "public.png" as CFString,
                                                             1,
                                                             nil) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    srgb.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let finalImage = srgb.makeImage() else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, finalImage, nil)
    CGImageDestinationFinalize(destination)
    print("  \(url.path) (\(pixelsWide)×\(pixelsHigh))")
}

@MainActor
func main() {
    // Otherwise the reset times come out in the region of whoever re-renders.
    UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    UserDefaults.standard.set("en_US", forKey: "AppleLocale")
    // Pin the selection so a leftover app default cannot change the picture.
    UserDefaults.standard.set(MenuBarStyle.both.rawValue, forKey: MenuBarStyle.defaultsKey)
    // The default blue accent, whatever the machine rendering this has chosen.
    UserDefaults.standard.setVolatileDomain(["AppleAccentColor": 4],
                                            forName: UserDefaults.argumentDomain)

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()

    let store = AccountStore(fixture: fixtureAccount, display: fixtureDisplay())
    for appearance in Appearance.allCases {
        write(MenuBarStrip(appearance: appearance), appearance: appearance, to: "menubar")
        shootPopover(store: store, appearance: appearance)
    }
}

main()
