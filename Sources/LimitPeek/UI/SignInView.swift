import SwiftUI

/// First-run sign-in: opens the browser, takes the code the callback page
/// shows. No embedded web view, so the app never sees a password.
struct SignInView: View {
    @Environment(AccountStore.self) private var store
    @State private var pastedCode = ""
    @State private var didOpenBrowser = false
    @FocusState private var codeFieldFocused: Bool

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
                            didOpenBrowser = false
                            pastedCode = ""
                            store.cancelSignIn()
                        }
                        Spacer()
                        Button("Continue", action: submit)
                            .keyboardShortcut(.defaultAction)
                            .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || store.isRefreshing)
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
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func submit() {
        let code = pastedCode
        pastedCode = ""
        Task { await store.completeSignIn(pastedCode: code) }
    }
}
