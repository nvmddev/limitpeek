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
    /// from its own button. `onRestart` adds the "Start over" link and is only
    /// passed by the reauthentication flow.
    init(startsInCodeEntry: Bool = false,
         onCancel: (() -> Void)? = nil,
         onRestart: (() -> Void)? = nil) {
        _didOpenBrowser = State(initialValue: startsInCodeEntry)
        self.onCancel = onCancel
        self.onRestart = onRestart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LimitPeek")
                    .font(.headline)
                Text("Sign in to see your usage limits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if didOpenBrowser {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste the code from the browser:")
                        .font(.callout)
                    TextField("Authorization code", text: $pastedCode)
                        .textFieldStyle(.roundedBorder)
                        .focused($codeFieldFocused)
                        .onSubmit(submit)

                    HStack {
                        Button("Back") {
                            if let onCancel {
                                onCancel()
                            } else {
                                didOpenBrowser = false
                                pastedCode = ""
                                store.cancelSignIn()
                            }
                        }
                        .disabled(store.isSigningIn)
                        if let onRestart {
                            Button("Start over") {
                                pastedCode = ""
                                onRestart()
                            }
                            .buttonStyle(.link)
                            .disabled(store.isSigningIn)
                        }
                        Spacer()
                        Button("Continue", action: submit)
                            .keyboardShortcut(.defaultAction)
                            .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || store.isSigningIn)
                    }
                }
            } else {
                Button {
                    NSWorkspace.shared.open(store.beginSignIn())
                    didOpenBrowser = true
                    codeFieldFocused = true
                } label: {
                    Text("Sign in with Claude")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.critical(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only while signed out: a reauthentication still owns the account,
            // so the sign-out notice would be misleading there.
            if !store.isSignedIn, let notice = store.tokenCleanupNotice {
                VStack(alignment: .leading, spacing: 6) {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(Palette.warning(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") {
                        store.retryPendingTokenCleanup()
                    }
                    .buttonStyle(.link)
                }
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            // Reauthentication starts directly in the code-entry step.
            if didOpenBrowser { codeFieldFocused = true }
        }
    }

    private func submit() {
        let code = pastedCode
        guard !store.isSigningIn,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        Task { await store.completeSignIn(pastedCode: code) }
    }
}
