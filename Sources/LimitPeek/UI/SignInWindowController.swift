import AppKit
import SwiftUI

/// The sign-in step that needs a text field, which a menu cannot hold.
@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate {
    private let store: AccountStore
    private var window: NSWindow?

    init(store: AccountStore) {
        self.store = store
    }

    /// Opens the browser on a fresh authorization and the window for the code
    /// it shows. While a sign-in is under way it only brings the window back,
    /// since a fresh authorization would orphan the code already copied.
    func begin(below anchor: NSRect? = nil) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SignInView { [weak self] in self?.window?.close() }.environment(store)))
        window.title = "Sign In to LimitPeek"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The browser opens on top, and an agent app has no Dock icon or
        // ⌘-Tab entry to bring the window back.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        Self.place(window, below: anchor)
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSWorkspace.shared.open(store.beginSignIn())
    }

    /// Centred, it would cover the code on the browser page.
    private static func place(_ window: NSWindow, below anchor: NSRect?) {
        guard let anchor,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let width = window.frame.width
        let margin: CGFloat = 8
        let x = min(max(anchor.midX - width / 2, visible.minX + margin), visible.maxX - width - margin)
        window.setFrameTopLeftPoint(NSPoint(x: x, y: visible.maxY - margin))
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        store.cancelSignIn()
    }
}
