import SwiftUI

/// Takes the code the browser shows once the user allows access. No embedded
/// web view, so the app never sees a password.
struct SignInView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var code = ""
    @FocusState private var isCodeFieldFocused: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuHeader(title: "Paste the code from your browser",
                       subtitle: "Claude shows it after you allow access.")

            TextField("Authorization Code", text: $code, prompt: Text("Authorization code"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($isCodeFieldFocused)
                .onSubmit(submit)

            if let error = store.lastError {
                MenuNote(text: error, color: Palette.critical)
            }

            HStack(spacing: 8) {
                Button("Open Browser Again") {
                    code = ""
                    openURL(store.beginSignIn())
                }
                .disabled(store.isSigningIn)
                Spacer(minLength: 0)
                if store.isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel", action: onFinish)
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 400)
        // The window is not key yet when onAppear runs.
        .defaultFocus($isCodeFieldFocused, true)
    }

    private var canSubmit: Bool {
        !store.isSigningIn && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let code = code
        Task {
            if await store.completeSignIn(pastedCode: code) { onFinish() }
        }
    }
}
