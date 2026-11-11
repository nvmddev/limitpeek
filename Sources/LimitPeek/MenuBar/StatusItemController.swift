import AppKit
import SwiftUI

/// The status item and its menu. The menu is rebuilt from the store when it
/// opens and again whenever what it shows changes while it is open. Usage rows
/// are SwiftUI views hosted in menu items; everything else is a native item.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let store: AccountStore
    private let launchAtLoginStatus: @MainActor () -> LaunchAtLoginStatus
    private let signInWindow: SignInWindowController
    private var statusItem: NSStatusItem?
    private var labelKey: MenuBarLabel.Key?
    private var style = MenuBarStyle.saved {
        didSet {
            MenuBarStyle.saved = style
            renderLabel()
        }
    }

    private var loginStatus = LaunchAtLoginStatus.disabled
    private var isMenuOpen = false
    /// Tells the current menu session from earlier ones whose observation
    /// callbacks may still arrive.
    private var menuSession = 0
    private weak var refreshItem: NSMenuItem?
    private var captionTimer: Timer?

    init(store: AccountStore,
         launchAtLoginStatus: @escaping @MainActor () -> LaunchAtLoginStatus = { LoginItem.status }) {
        self.store = store
        self.launchAtLoginStatus = launchAtLoginStatus
        signInWindow = SignInWindowController(store: store)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    /// Puts the item in the menu bar. The README renderer uses the menu
    /// without it.
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item
        observeLabel()
    }

    // MARK: - Label

    private func observeLabel() {
        withObservationTracking(renderLabel) { [weak self] in
            Task { @MainActor in self?.observeLabel() }
        }
    }

    /// Equal keys draw the same image, so a poll that changes nothing on
    /// screen leaves the status item alone.
    private func renderLabel() {
        let key = MenuBarLabel.Key(percent: store.display?.sessionPercent,
                                   style: style,
                                   isSignedIn: store.isSignedIn)
        guard key != labelKey else { return }
        labelKey = key
        statusItem?.button?.image = MenuBarLabel.image(for: key)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginStatus = launchAtLoginStatus()
        menuSession += 1
        rebuild(session: menuSession)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        store.retryPendingTokenCleanup()
        scheduleCaptionUpdate()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        captionTimer?.invalidate()
        captionTimer = nil
    }

    private func rebuild(session: Int) {
        withObservationTracking(populate) { [weak self] in
            Task { @MainActor in
                guard let self, self.isMenuOpen, self.menuSession == session else { return }
                self.rebuild(session: session)
            }
        }
    }

    private func populate() {
        menu.removeAllItems()

        guard let account = store.account else {
            addView(MenuHeader(title: "LimitPeek", subtitle: "Sign in to see your usage limits."))
            menu.addItem(.separator())
            if let error = store.lastError {
                addView(MenuNote(text: error, color: Palette.critical))
            }
            if let notice = store.tokenCleanupNotice {
                addView(MenuNote(text: notice, color: Palette.warning))
            }
            menu.addItem(item("Sign In with Claude…", action: #selector(signIn)))
            menu.addItem(.separator())
            menu.addItem(item("Quit LimitPeek", action: #selector(quit), key: "q"))
            return
        }

        addView(MenuHeader(title: "Usage Limits", subtitle: account.subtitle))
        menu.addItem(.separator())
        if let rows = store.display?.rows, !rows.isEmpty {
            for row in rows { addView(LimitRow(row: row)) }
        } else if store.isRefreshing {
            addView(Label { Text("Loading…") } icon: { ProgressView().controlSize(.small) }
                .foregroundStyle(.secondary))
        } else if store.lastError == nil {
            addView(Text("No usage data").foregroundStyle(.secondary))
        }
        if let error = store.lastError {
            addView(MenuNote(text: error, color: Palette.critical))
        }
        menu.addItem(.separator())

        if store.needsReauthentication {
            menu.addItem(item("Sign In Again…", subtitle: reauthenticationReason, action: #selector(signIn)))
        }
        let refresh = item("Refresh", action: #selector(refreshNow), key: "r")
        refreshItem = refresh
        updateCaption()
        menu.addItem(refresh)
        menu.addItem(item("Usage on claude.ai…", action: #selector(openUsageSettings)))
        menu.addItem(.separator())
        menu.addItem(settingsItem())
        menu.addItem(.separator())
        menu.addItem(item("Sign Out", action: #selector(signOut)))
        menu.addItem(item("Quit LimitPeek", action: #selector(quit), key: "q"))
    }

    /// The checkmarks live here: one checked item in the main menu indents
    /// every title there and would push the usage rows off center.
    private func settingsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(.sectionHeader(title: "Show in Menu Bar"))
        for option in MenuBarStyle.allCases {
            let choice = item(option.title, action: #selector(chooseStyle(_:)))
            choice.representedObject = option
            choice.state = option == style ? .on : .off
            submenu.addItem(choice)
        }
        submenu.addItem(.separator())
        let launchAtLogin = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = loginStatus.isEnabled ? .on : .off
        launchAtLogin.isEnabled = loginStatus != .unavailable
        submenu.addItem(launchAtLogin)
        if loginStatus.needsApproval {
            submenu.addItem(item("Approve in System Settings…", action: #selector(openLoginItemSettings)))
        }

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.submenu = submenu
        return settings
    }

    private var reauthenticationReason: String {
        switch store.authIssue {
        case .missingToken: "No saved sign-in"
        case .forbidden: "Not permitted"
        case .sessionExpired, nil: "Session expired"
        }
    }

    private func item(_ title: String, subtitle: String? = nil,
                      action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if #available(macOS 14.4, *) { item.subtitle = subtitle }
        return item
    }

    private func addView(_ content: some View) {
        let host = NSHostingView(rootView: content
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 5)
            .frame(width: MenuMetrics.width, alignment: .leading))
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        menu.addItem(item)
    }

    // MARK: - Refresh caption

    private func updateCaption(now: Date = .now) {
        guard let refreshItem else { return }
        refreshItem.isEnabled = store.canRefresh(at: now)
        if #available(macOS 14.4, *) {
            refreshItem.subtitle = RefreshCaption.text(isRefreshing: store.isRefreshing,
                                                       rateLimitedUntil: store.rateLimitedUntil,
                                                       fetchedAt: store.display?.fetchedAt,
                                                       now: now)
        }
    }

    /// Keeps "Updated … ago" and the retry countdown current while the menu is open.
    private func scheduleCaptionUpdate() {
        let interval = RefreshCaption.tickInterval(after: .now, deadline: store.rateLimitedUntil)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isMenuOpen else { return }
                self.updateCaption()
                self.scheduleCaptionUpdate()
            }
        }
        // Common modes, or it would not fire while the menu tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
        captionTimer = timer
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        Task { await store.refresh() }
    }

    @objc private func openUsageSettings() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        if let option = sender.representedObject as? MenuBarStyle { style = option }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!loginStatus.isEnabled)
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openLoginItemSettings() {
        LoginItem.openSystemSettings()
    }

    @objc private func signIn() {
        signInWindow.begin()
    }

    @objc private func signOut() {
        store.signOut()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum MenuMetrics {
    static let width: CGFloat = 320
    /// Where native items start their titles and end their key equivalents,
    /// measured on macOS 27, so hosted rows line up with them on both sides.
    static let inset: CGFloat = 16
}

/// The Refresh item's subtitle. Pure, so the cadence and wording are testable.
enum RefreshCaption {
    static func text(isRefreshing: Bool, rateLimitedUntil: Date?, fetchedAt: Date?, now: Date) -> String? {
        if isRefreshing { return "Updating…" }
        if let rateLimitedUntil, rateLimitedUntil.timeIntervalSince(now) >= 1 {
            let left = Duration.seconds(rateLimitedUntil.timeIntervalSince(now))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 1))
            return "Rate limited · retrying in \(left)"
        }
        guard let fetchedAt else { return nil }
        if now.timeIntervalSince(fetchedAt) < 60 { return "Updated just now" }
        return "Updated \(fetchedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))"
    }

    /// Once a second only in the final minute before a rate-limit deadline,
    /// when the countdown moves; every 30 s otherwise.
    static func tickInterval(after date: Date, deadline: Date?) -> TimeInterval {
        guard let deadline, date < deadline, deadline.timeIntervalSince(date) <= 60 else { return 30 }
        return 1
    }
}
