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
    /// Standing in for the window's material, which renders as clear.
    var popoverBackground: Color { self == .dark ? Color(white: 0.16) : Color(white: 0.97) }
}

struct MenuBarStrip: View {
    let appearance: Appearance

    var body: some View {
        HStack(spacing: 24) {
            MenuBarLabel.Content(percent: 40, tint: appearance.menuBarForeground)
            MenuBarLabel.Content(percent: 84, tint: .orange)
            MenuBarLabel.Content(percent: 97, tint: .red)
        }
    }
}

struct PopoverShot: View {
    let appearance: Appearance
    let store: AccountStore

    var body: some View {
        UsagePopover(refresher: Refresher())
            .environment(store)
            .background(appearance.popoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(appearance == .dark ? 0.18 : 0.10),
                                  lineWidth: 0.5)
            }
            .padding(10)
    }
}

@MainActor
func write(_ view: some View, appearance: Appearance, to name: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance.colorScheme))
    renderer.scale = scale
    renderer.isOpaque = false

    var image: CGImage?
    appearance.nsAppearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
    guard let image else { fatalError("could not render \(name)") }

    let url = outputDirectory.appendingPathComponent("\(name)-\(appearance.rawValue).png")
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(url.lastPathComponent)")
    }
    try! data.write(to: url)
    print("  \(url.path) (\(image.width)×\(image.height))")
}

@MainActor
func main() {
    // Otherwise the reset times come out in the region of whoever re-renders.
    UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    UserDefaults.standard.set("en_US", forKey: "AppleLocale")

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    let store = AccountStore(fixture: fixtureAccount, display: fixtureDisplay())
    for appearance in Appearance.allCases {
        write(MenuBarStrip(appearance: appearance), appearance: appearance, to: "menubar")
        write(PopoverShot(appearance: appearance, store: store), appearance: appearance, to: "popover")
    }
}

main()
