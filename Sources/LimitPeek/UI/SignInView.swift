import SwiftUI

/// Opens the browser and takes the code the callback page shows. No embedded
/// web view, so the app never sees a password.
struct SignInView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var pastedCode = ""
    @State private var didOpenBrowser: Bool
    @FocusState private var codeFieldFocused: Bool
    private let onCancel: (() -> Void)?
    private let onRestart: (() -> Void)?

    /// `startsInCodeEntry` is for a reauthentication, where the caller has
    /// already opened the browser and kept the PKCE challenge in the store.
    /// The ordinary first sign-in keeps the default and opens the browser
    /// from its own button. `onRestart` adds the "Start Over" button and is only
    /// passed by the reauthentication flow.
    init(startsInCodeEntry: Bool = false,
         onCancel: (() -> Void)? = nil,
         onRestart: (() -> Void)? = nil) {
        _didOpenBrowser = State(initialValue: startsInCodeEntry)
        self.onCancel = onCancel
        self.onRestart = onRestart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "LimitPeek", subtitle: "Sign in to see your usage limits.")

            VStack(alignment: .leading, spacing: 10) {
                if didOpenBrowser {
                    codeEntry
                } else {
                    Button {
                        NSWorkspace.shared.open(store.beginSignIn())
                        didOpenBrowser = true
                        codeFieldFocused = true
                    } label: {
                        Text("Sign in with Claude")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Palette.critical(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Only while signed out: a reauthentication still owns the account,
                // so the sign-out notice would be misleading there.
                if !store.isSignedIn, let notice = store.tokenCleanupNotice {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(Palette.warning(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Try Again") {
                            store.retryPendingTokenCleanup()
                        }
                        .buttonStyle(.link)
                        .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal, PanelMetrics.margin)
            .padding(.top, 14)
            .padding(.bottom, 9)

            PanelSeparator()

            MenuActionRow(title: "Quit LimitPeek", shortcut: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, PanelMetrics.highlightInset)
        .frame(width: PanelMetrics.width)
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Authorization Code", text: $pastedCode,
                      prompt: Text("Paste the code from your browser"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($codeFieldFocused)
                .onSubmit(submit)

            // A tinted bordered button colors its label, which reads as
            // disabled, so only Continue keeps the palette's tint.
            HStack(spacing: 8) {
                if let onRestart {
                    Button("Start Over") {
                        pastedCode = ""
                        onRestart()
                    }
                    .tint(nil)
                    .disabled(store.isSigningIn)
                }
                Spacer(minLength: 0)
                if store.isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Back") {
                    if let onCancel {
                        onCancel()
                    } else {
                        didOpenBrowser = false
                        pastedCode = ""
                        store.cancelSignIn()
                    }
                }
                .keyboardShortcut(.cancelAction)
                .tint(nil)
                .disabled(store.isSigningIn)
                Button("Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || store.isSigningIn)
            }
        }
        // Reauthentication opens straight into this step, and the window is
        // not key yet when onAppear runs, so this is the reliable hook.
        .defaultFocus($codeFieldFocused, true)
    }

    private func submit() {
        let code = pastedCode
        guard !store.isSigningIn,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        Task { await store.completeSignIn(pastedCode: code) }
    }
}
