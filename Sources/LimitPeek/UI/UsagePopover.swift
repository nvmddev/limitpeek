import SwiftUI

struct UsagePopover: View {
    @Environment(AccountStore.self) private var store
    let refresher: Refresher

    var body: some View {
        Group {
            if store.isSignedIn {
                signedIn
            } else {
                SignInView()
            }
        }
        .onAppear { refresher.refreshIfStale() }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            limits
            Divider().padding(.vertical, 6)
            actions
        }
        .padding(.vertical, 8)
        .frame(width: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Your usage limits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let account = store.selectedAccount {
                Text(account.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var limits: some View {
        if let display = store.display, !display.rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(display.rows) { row in
                    LimitRow(row: row)
                }
            }
            .padding(.horizontal, 14)
        } else if store.isRefreshing {
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        }

        if let error = store.lastError {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 10)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            MenuActionRow(title: "Refresh", trailing: freshnessText) {
                Task { await store.refresh() }
            }
            .disabled(store.isRefreshing)

            LaunchAtLoginRow()

            MenuActionRow(title: "Usage settings…") {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            }

            Divider().padding(.vertical, 6).padding(.horizontal, 8)

            MenuActionRow(title: "Sign Out") { store.signOut() }
            MenuActionRow(title: "Quit", shortcut: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var freshnessText: String? {
        if store.isRefreshing { return "Updating…" }
        if store.rateLimit != nil, let countdown = refresher.retryCountdown { return countdown }
        guard let fetchedAt = store.display?.fetchedAt else { return nil }
        if Date().timeIntervalSince(fetchedAt) < 60 { return "Just updated" }
        return fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

/// A row styled like a menu item: full-width hover highlight, no button chrome.
struct MenuActionRow: View {
    let title: String
    var trailing: String?
    var shortcut: Character?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(title: String,
         trailing: String? = nil,
         shortcut: Character? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13))
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(isHovering ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering && isEnabled ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: Character?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(key))
        } else {
            content
        }
    }
}

/// Separate so the SMAppService status is read once per appearance, not on
/// every redraw.
struct LaunchAtLoginRow: View {
    @State private var isEnabled = false
    @State private var isHovering = false

    var body: some View {
        Button {
            let target = !isEnabled
            do {
                try LoginItem.setEnabled(target)
                isEnabled = target
            } catch {
                isEnabled = LoginItem.isEnabled
            }
        } label: {
            HStack(spacing: 8) {
                Text("Launch at Login").font(.system(size: 13))
                Spacer(minLength: 8)
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
        .onAppear { isEnabled = LoginItem.isEnabled }
    }
}
