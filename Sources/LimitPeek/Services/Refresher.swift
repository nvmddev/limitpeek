import AppKit

/// Decides when to poll: a while after the last request, whoever made it.
/// Paused while signed out or reauthenticating and while the machine or its
/// displays sleep, stretched in Low Power Mode and after a 429.
@MainActor
final class Refresher {
    private let store: AccountStore
    private var schedule = PollSchedule()
    private var pollTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    init(store: AccountStore) {
        self.store = store
    }

    func start() {
        guard observers.isEmpty else { return }
        store.onSessionStateChange = { [weak self] _ in self?.resume() }
        observe(NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification) { $0.pause() }
        observe(NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification) { $0.resume() }
        resume()
    }

    private func observe(_ names: Notification.Name...,
                         perform action: @escaping @Sendable @MainActor (Refresher) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { action(self) }
                }
            })
        }
    }

    /// Restarts the loop; it works out from the store when the next poll is due.
    private func resume() {
        pause()
        guard store.sessionState == .signedIn else { return }
        pollTask = Task { [weak self] in await self?.poll() }
    }

    private func pause() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        while !Task.isCancelled, store.sessionState == .signedIn {
            let due = schedule.nextPoll(after: store.lastRefreshAt,
                                        rateLimitedUntil: store.rateLimitedUntil,
                                        isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
            let wait = due.timeIntervalSinceNow
            if wait > 0 {
                do {
                    try await Task.sleep(for: .seconds(wait), tolerance: .seconds(15))
                } catch {
                    return
                }
            } else {
                schedule.record(await store.refresh())
            }
        }
    }
}

/// How long to wait between polls. Separated so the backoff can be tested
/// without timers or network.
struct PollSchedule: Sendable {
    static let normalInterval: TimeInterval = 180
    /// Low Power Mode, and after a 429 until a poll lands again.
    static let slowInterval: TimeInterval = 300

    private(set) var isBackingOff = false

    mutating func record(_ outcome: AccountStore.RefreshOutcome) {
        switch outcome {
        case .updated: isBackingOff = false
        case .rateLimited: isBackingOff = true
        case .failed, .skipped, .signedOut, .requiresReauthentication: break
        }
    }

    func interval(isLowPowerMode: Bool) -> TimeInterval {
        isBackingOff || isLowPowerMode ? Self.slowInterval : Self.normalInterval
    }

    /// Never before a rate-limit deadline; at once when nothing was requested yet.
    func nextPoll(after lastRequest: Date, rateLimitedUntil: Date?, isLowPowerMode: Bool) -> Date {
        max(lastRequest.addingTimeInterval(interval(isLowPowerMode: isLowPowerMode)),
            rateLimitedUntil ?? .distantPast)
    }
}
