// Draws the README pictures with the app's own code, so they cannot drift
// from what ships.
//
//   scripts/make-readme-art.sh [output directory]

import AppKit
import SwiftUI

/// The README shows the pictures at a third of their pixel size, so they stay
/// sharp on a Retina display.
let scale = 3.0
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
    let size = NSSize(width: images.map(\.size.width).reduce(0, +) + spacing * Double(images.count - 1),
                      height: images.map(\.size.height).max() ?? 0)
    writePNG(named: "menubar-\(appearance.rawValue)", size: size, appearance: appearance) {
        var x = 0.0
        for image in images {
            let rect = NSRect(x: x, y: 0, width: image.size.width, height: image.size.height)
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
func writePNG(named name: String, size: NSSize, appearance: Appearance, draw: () -> Void) {
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
/// server draws its material and shadow. That needs Screen Recording
/// permission for the terminal running the script. The capture comes out at
/// the main display's scale, with the shadow.
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

    let url = outputDirectory.appendingPathComponent("menu-\(appearance.rawValue).png")
    // Fires inside the menu's tracking loop, which `popUp` runs until cancelled.
    let timer = Timer(timeInterval: 1, repeats: false) { _ in
        MainActor.assumeIsolated {
            capture(windowOf: controller.menu, excluding: backdrop, to: url)
            controller.menu.cancelTracking()
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    controller.menu.popUp(positioning: nil, at: origin, in: nil)
    backdrop.orderOut(nil)

    let pixels = NSImageRep(contentsOf: url).map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? "?"
    print("  \(url.path) (\(pixels))")
}

@MainActor
func capture(windowOf menu: NSMenu, excluding backdrop: NSWindow, to url: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let number = windows.lazy
        .filter({ ($0[kCGWindowOwnerPID as String] as? Int32) == pid })
        .compactMap({ $0[kCGWindowNumber as String] as? Int })
        .first(where: { $0 != backdrop.windowNumber }) else {
        fatalError("the menu window is not on screen")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l\(number)", url.path]
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
