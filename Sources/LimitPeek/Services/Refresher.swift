import AppKit

/// Decides when to poll: a while after the last request, whoever made it.
/// Paused while signed out or reauthenticating and while the machine or its
/// displays sleep, stretched in Low Power Mode and after a 429.
@MainActor
final class Refresher {
    private let store: AccountStore
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
            let due = PollSchedule.nextPoll(after: store.lastRefreshAt,
                                            rateLimitedAt: store.rateLimitedAt,
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
                await store.refresh()
            }
        }
    }
}

/// How long to wait between polls. Separated so the backoff can be tested
/// without timers or network.
enum PollSchedule {
    static let normalInterval: TimeInterval = 120
    /// Low Power Mode, and for `recoveryPeriod` after a 429.
    static let slowInterval: TimeInterval = 300
    static let recoveryPeriod: TimeInterval = 1200

    static func interval(after lastRequest: Date, rateLimitedAt: Date?, isLowPowerMode: Bool) -> TimeInterval {
        let isRecovering = rateLimitedAt.map { lastRequest.timeIntervalSince($0) < recoveryPeriod } ?? false
        return isRecovering || isLowPowerMode ? slowInterval : normalInterval
    }

    /// Never before a rate-limit deadline; at once when nothing was requested yet.
    static func nextPoll(after lastRequest: Date, rateLimitedAt: Date?, rateLimitedUntil: Date?,
                         isLowPowerMode: Bool) -> Date {
        let interval = interval(after: lastRequest, rateLimitedAt: rateLimitedAt, isLowPowerMode: isLowPowerMode)
        return max(lastRequest.addingTimeInterval(interval), rateLimitedUntil ?? .distantPast)
    }
}
