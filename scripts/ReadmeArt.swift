// Draws the README pictures with the app's own code, so they cannot drift
// from what ships.
//
//   scripts/make-readme-art.sh [output directory]

import AppKit
import SwiftUI

/// The README shows the menu bar label at a third of its pixel size, so it
/// stays sharp on a Retina display.
let labelScale = 3.0
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs",
                          isDirectory: true)

let fixtureAccount = Account(id: "00000000-0000-0000-0000-000000000000",
                             displayName: "Alex Rivera",
                             organizationName: "Acme Corp")

/// Built from the response the tests pin, so the menu shows buckets the API
/// really returns. Every date the API supplied moves by the same amount, which
/// puts the 5-hour reset three hours out and leaves the weekly one where the
/// API had it relative to that.
@MainActor
func fixtureDisplay(now: Date = .now) -> UsageDisplay {
    let json = try! Data(contentsOf: URL(fileURLWithPath: "Tests/LimitPeekTests/Fixtures/usage.json"))
    let response = try! API.makeDecoder().decode(UsageResponse.self, from: json)
    var display = UsageDisplay(response, fetchedAt: now)

    guard let session = display.rows.first(where: { $0.kind == "session" })?.resetsAt else {
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

    var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
    /// What the menu bar tints a template image with.
    var menuBarForeground: NSColor { self == .dark ? .white : .black }
    /// Behind the label, so the light and the dark picture can sit side by
    /// side on either README theme.
    var menuBarBackground: NSColor { self == .dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1) }
    /// What sits behind the menu. Plain and neutral, so the translucent
    /// material looks the same on every machine instead of picking up the
    /// desktop.
    var backdrop: NSColor { self == .dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.9, alpha: 1) }
}

/// The label at 40%, 84% and 97%, drawn the way the menu bar draws it:
/// template images in the bar's foreground, tinted ones as they are.
@MainActor
func writeMenuBarStrip(appearance: Appearance) {
    let images = [40.0, 84, 97].map {
        MenuBarLabel.image(for: .init(percent: $0, style: .both, isSignedIn: true))
    }
    let spacing = 24.0
    let padding = NSSize(width: 12, height: 6)
    let size = NSSize(width: images.map(\.size.width).reduce(0, +) + spacing * Double(images.count - 1)
                          + 2 * padding.width,
                      height: (images.map(\.size.height).max() ?? 0) + 2 * padding.height)
    writePNG(named: "menubar-\(appearance.rawValue)", size: size, scale: labelScale, appearance: appearance) {
        let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: 8, yRadius: 8)
        appearance.menuBarBackground.setFill()
        background.fill()
        appearance.menuBarForeground.withAlphaComponent(0.1).setStroke()
        background.stroke()

        var x = padding.width
        for image in images {
            let rect = NSRect(x: x, y: padding.height, width: image.size.width, height: image.size.height)
            if image.isTemplate {
                NSImage(size: image.size, flipped: false) { bounds in
                    image.draw(in: bounds)
                    appearance.menuBarForeground.set()
                    bounds.fill(using: .sourceIn)
                    return true
                }.draw(in: rect)
            } else {
                image.draw(in: rect)
            }
            x += image.size.width + spacing
        }
    }
}

/// Draws into an sRGB context, so the PNG carries an sRGB tag; untagged
/// device RGB shifts the colors in some viewers.
@MainActor
func writePNG(named name: String, size: NSSize, scale: Double, appearance: Appearance, draw: () -> Void) {
    let url = outputDirectory.appendingPathComponent("\(name).png")
    guard let context = CGContext(data: nil,
                                  width: Int((size.width * scale).rounded()),
                                  height: Int((size.height * scale).rounded()),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create a bitmap context for \(name)")
    }
    context.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    appearance.nsAppearance.performAsCurrentDrawingAppearance(draw)
    NSGraphicsContext.restoreGraphicsState()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("  \(url.path) (\(image.width)×\(image.height))")
}

/// The menu is shot on screen with `screencapture`, because only the window
/// server draws its material. That needs Screen Recording permission for the
/// terminal running the script.
@MainActor
func shootMenu(store: AccountStore, appearance: Appearance) {
    NSApp.appearance = appearance.nsAppearance
    let controller = StatusItemController(store: store, launchAtLoginStatus: { .disabled })
    // On the half of the screen away from the pointer, which would otherwise
    // highlight the item under it.
    let visible = NSScreen.main!.visibleFrame
    let x = NSEvent.mouseLocation.x < visible.midX
        ? visible.maxX - MenuMetrics.width - 200
        : visible.minX + 200
    let origin = NSPoint(x: x, y: visible.maxY - 120)

    let backdrop = NSWindow(contentRect: NSRect(x: origin.x - 120, y: origin.y - 640,
                                                width: MenuMetrics.width + 240, height: 760),
                            styleMask: .borderless, backing: .buffered, defer: false)
    backdrop.backgroundColor = appearance.backdrop
    backdrop.level = .floating
    backdrop.orderFrontRegardless()

    let temporary = FileManager.default.temporaryDirectory
    let shape = temporary.appendingPathComponent("limitpeek-menu-shape.png")
    let screen = temporary.appendingPathComponent("limitpeek-menu-screen.png")
    // Fires inside the menu's tracking loop, which `popUp` runs until cancelled.
    let timer = Timer(timeInterval: 1, repeats: false) { _ in
        MainActor.assumeIsolated {
            capture(excluding: backdrop, shape: shape, screen: screen)
            controller.menu.cancelTracking()
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    controller.menu.popUp(positioning: nil, at: origin, in: nil)
    backdrop.orderOut(nil)

    writeMenu(named: "menu-\(appearance.rawValue)", shape: shape, screen: screen, appearance: appearance)
    try? FileManager.default.removeItem(at: shape)
    try? FileManager.default.removeItem(at: screen)
}

/// Two shots: the menu window alone, for its exact outline, and the screen
/// under it, for its colors. Alone, the window server draws the material over
/// nothing, which turns the light menu gray.
@MainActor
func capture(excluding backdrop: NSWindow, shape: URL, screen: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let window = windows.first(where: {
              ($0[kCGWindowOwnerPID as String] as? Int32) == pid
                  && ($0[kCGWindowNumber as String] as? Int) != backdrop.windowNumber
          }),
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
              .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }) else {
        fatalError("the menu window is not on screen")
    }
    let region = [bounds.minX, bounds.minY, bounds.width, bounds.height]
        .map { String(Int($0.rounded())) }.joined(separator: ",")
    screencapture("-o", "-l\(number)", shape.path)
    screencapture("-R\(region)", screen.path)
}

func screencapture(_ arguments: String...) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x"] + arguments
    do {
        try process.run()
    } catch {
        fatalError("could not run screencapture: \(error)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("screencapture failed; grant the terminal Screen Recording permission")
    }
}

/// The window shot with its body replaced by the screen shot, cropped to what
/// is visible, at the display's scale so nothing is resampled. The window
/// draws its own shadow, so that comes along.
@MainActor
func writeMenu(named name: String, shape: URL, screen: URL, appearance: Appearance) {
    func load(_ url: URL) -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("could not read \(url.path)")
        }
        return image
    }
    let window = load(shape)
    let colors = load(screen)
    guard window.width == colors.width, window.height == colors.height else {
        fatalError("the window and screen shots differ in size")
    }
    let (body, menu) = bodyMask(of: window)
    let scale = NSScreen.main!.backingScaleFactor
    // Measured from the menu rather than from where the shadow fades out,
    // which differs per appearance, so the light and dark pictures match.
    let side = 36 * scale, top = 24 * scale, bottom = 48 * scale
    let visible = CGRect(x: menu.minX - side, y: menu.minY - top,
                         width: menu.width + 2 * side, height: menu.height + top + bottom)
        .intersection(CGRect(x: 0, y: 0, width: window.width, height: window.height))
    let size = NSSize(width: visible.width / scale, height: visible.height / scale)

    writePNG(named: name, size: size, scale: scale, appearance: appearance) {
        let context = NSGraphicsContext.current!.cgContext
        let rect = CGRect(origin: .zero, size: size)
        context.draw(window.cropping(to: visible)!, in: rect)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.draw(colors.cropping(to: visible)!, in: rect)
        context.setBlendMode(.destinationIn)
        context.draw(body.cropping(to: visible)!, in: rect)
        context.endTransparencyLayer()
    }
}

/// Where the window is the menu rather than its shadow, which never gets
/// near opaque, and the menu's pixel box.
func bodyMask(of window: CGImage) -> (mask: CGImage, menu: CGRect) {
    let width = window.width, height = window.height
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let data = context.data else {
        fatalError("could not create a bitmap context for the mask")
    }
    context.draw(window, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let alpha = Double(pixels[index + 3]) / 255
            let body = UInt8((min(max((alpha - 0.35) / 0.65, 0), 1) * 255).rounded())
            if body == 255 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            for channel in 0..<4 { pixels[index + channel] = body }
        }
    }
    guard let mask = context.makeImage(), minX <= maxX else { fatalError("the menu shot has no menu") }
    return (mask, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

@MainActor
func main() {
    // Otherwise the reset times come out in the region of whoever re-renders.
    UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    UserDefaults.standard.set("en_US", forKey: "AppleLocale")
    // Pin the selection so a leftover app default cannot change the picture.
    MenuBarStyle.saved = .both

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()

    let store = AccountStore(fixture: fixtureAccount, display: fixtureDisplay())
    for appearance in Appearance.allCases {
        writeMenuBarStrip(appearance: appearance)
        shootMenu(store: store, appearance: appearance)
    }
}

main()
