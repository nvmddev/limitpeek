import SwiftUI

struct UsagePopover: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MenuBarStyle.defaultsKey) private var style = MenuBarStyle.both
    @State private var isReauthenticating = false
    let refresher: Refresher

    var body: some View {
        Group {
            if store.isSignedIn {
                if isReauthenticating {
                    // The browser is already open and the pending PKCE is in
                    // the store, so only the paste step is left.
                    SignInView(startsInCodeEntry: true,
                               onCancel: {
                                   store.cancelSignIn()
                                   isReauthenticating = false
                               },
                               onRestart: {
                                   beginReauthentication()
                               })
                } else {
                    signedIn
                }
            } else {
                SignInView()
            }
        }
        .tint(Palette.accent(for: colorScheme))
        .panelBackground()
        .onAppear {
            refresher.refreshIfStale()
            // A keychain cleanup left over from sign-out; best effort.
            store.retryPendingTokenCleanup()
        }
        .onChange(of: store.needsReauthentication) { _, needsReauthentication in
            // A successful reauthentication returns to the normal signed-in view.
            if !needsReauthentication { isReauthenticating = false }
        }
        .onChange(of: store.isSignedIn) { _, isSignedIn in
            if !isSignedIn { isReauthenticating = false }
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Usage Limits", subtitle: store.selectedAccount?.subtitle)
            limits
                .padding(.top, 12)
                .padding(.bottom, 4)
            PanelSeparator()
            actions
        }
        .padding(.top, 12)
        .padding(.bottom, PanelMetrics.highlightInset)
        .frame(width: PanelMetrics.width)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let display = store.display, !display.rows.isEmpty {
                ForEach(display.rows) { row in
                    LimitRow(row: row)
                }
            } else if store.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                }
                .foregroundStyle(.secondary)
            } else if store.lastError == nil {
                Text("No usage data")
                    .foregroundStyle(.secondary)
            }

            if let error = store.lastError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Palette.critical(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PanelMetrics.margin)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if store.needsReauthentication {
                MenuActionRow(title: "Sign In Again…",
                              trailing: reauthenticationDetail) {
                    beginReauthentication()
                }
            }

            TimelineView(RefreshTimelineSchedule(deadline: store.rateLimit?.deadline)) { context in
                MenuActionRow(title: "Refresh", trailing: freshnessText(now: context.date)) {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing
                          || isRateLimited(at: context.date)
                          || store.needsReauthentication)
            }

            MenuActionRow(title: "Usage Settings…") {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
            }

            PanelSeparator()

            MenuBarStyleRow(style: $style)
            LaunchAtLoginRow()

            PanelSeparator()

            MenuActionRow(title: "Sign Out") { store.signOut() }
            MenuActionRow(title: "Quit LimitPeek", shortcut: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func isRateLimited(at date: Date) -> Bool {
        guard let deadline = store.rateLimit?.deadline else { return false }
        return date < deadline
    }

    private func freshnessText(now: Date) -> String? {
        if store.isRefreshing { return "Updating…" }
        if store.rateLimit != nil, let countdown = refresher.retryCountdown { return countdown }
        guard let fetchedAt = store.display?.fetchedAt else { return nil }
        if now.timeIntervalSince(fetchedAt) < Refresher.popoverStaleAfter { return "Just updated" }
        return fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private var reauthenticationDetail: String {
        switch store.authIssue {
        case .missingToken: return "No saved sign-in"
        case .forbidden: return "Not permitted"
        case .sessionExpired, nil: return "Session expired"
        }
    }

    private func beginReauthentication() {
        NSWorkspace.shared.open(store.beginSignIn())
        isReauthenticating = true
    }
}

/// One tick per second only in the final minute before a rate-limit deadline,
/// when the retry countdown needs to move; 30 s earlier, after the deadline,
/// and in low-frequency mode. A `Retry-After` can be an hour, and redrawing
/// the whole row every second for that long is pure cost.
///
/// Not private: the cadence is pure and the tests can pin it.
struct RefreshTimelineSchedule: TimelineSchedule {
    var deadline: Date?

    static func tickInterval(after date: Date,
                             deadline: Date?,
                             mode: TimelineScheduleMode) -> TimeInterval {
        guard mode != .lowFrequency,
              let deadline,
              date < deadline,
              deadline.timeIntervalSince(date) <= 60
        else { return 30 }
        return 1
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(nextDate: startDate, deadline: deadline, mode: mode)
    }

    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date
        let deadline: Date?
        let mode: TimelineScheduleMode

        mutating func next() -> Date? {
            let date = nextDate
            nextDate = date.addingTimeInterval(
                RefreshTimelineSchedule.tickInterval(after: date,
                                                     deadline: deadline,
                                                     mode: mode))
            return date
        }
    }
}

/// Picks what the menu bar item shows. One segmented row rather than a menu
/// row per choice, which would outweigh everything above it. Drawn by hand
/// instead of a segmented `Picker`: AppKit paints the selected segment gray
/// whenever the panel is not key, so the accent would come and go.
struct MenuBarStyleRow: View {
    @Binding var style: MenuBarStyle
    @Namespace private var thumb
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PanelRow(title: "Menu Bar", alignment: .center) {
            HStack(spacing: 0) {
                ForEach(MenuBarStyle.allCases) { option in
                    segment(option)
                }
            }
            .padding(2)
            .background(Capsule().fill(.quaternary))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Menu Bar")
        }
    }

    private func segment(_ option: MenuBarStyle) -> some View {
        let isSelected = option == style
        return Button {
            withAnimation(.snappy(duration: 0.25)) { style = option }
        } label: {
            Text(option.shortTitle)
                .font(.subheadline.weight(isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                                 ? AnyShapeStyle(Palette.onAccent(for: colorScheme))
                                 : AnyShapeStyle(.secondary))
                .frame(width: 54, height: 18)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.tint)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(option.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Separate so the SMAppService status is read once per appearance, not on
/// every redraw.
struct LaunchAtLoginRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var status: LaunchAtLoginStatus = .disabled
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelRow(title: "Launch at Login", alignment: .center) {
                Toggle("Launch at Login", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(status == .unavailable)
            }
            .onAppear(perform: refreshStatus)
            // Approval can change while the popover is open, and the popover
            // itself does not get a scenePhase change when the app returns.
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshStatus()
            }

            if status.needsApproval {
                Button("Approve in System Settings…") {
                    LoginItem.openSystemSettings()
                }
                .buttonStyle(.link)
                .font(.subheadline)
                .padding(.horizontal, PanelMetrics.margin)
                .padding(.bottom, 4)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(Palette.critical(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PanelMetrics.margin)
                    .padding(.bottom, 4)
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding(get: { status.isEnabled }, set: setEnabled)
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshStatus()
    }

    private func refreshStatus() {
        status = LoginItem.status
    }
}
