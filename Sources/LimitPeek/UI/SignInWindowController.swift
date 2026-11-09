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
    func begin() {
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
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        NSWorkspace.shared.open(store.beginSignIn())
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        store.cancelSignIn()
    }
}
