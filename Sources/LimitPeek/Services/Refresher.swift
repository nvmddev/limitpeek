import AppKit
import Foundation
import Observation

/// Decides when to poll: paused while the machine sleeps, stretched in Low
/// Power Mode.
@MainActor
@Observable
final class Refresher {
    static let popoverStaleAfter: TimeInterval = 10

    private let normalInterval: Duration = .seconds(180)
    private let lowPowerInterval: Duration = .seconds(300)
    private let maxInterval: Duration = .seconds(300)
    private let tolerance: Duration = .seconds(15)

    /// Multiplies the interval while the server is answering 429. Doubling on a
    /// rejection and halving on a clean poll settles just under whatever the
    /// endpoint actually allows, instead of alternating between the base rate
    /// and a rejection forever.
    private var penalty = 1
    private(set) var nextPollAt = Date.distantPast

    var retryCountdown: String? {
        let seconds = nextPollAt.timeIntervalSinceNow
        guard seconds >= 1 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter.string(from: seconds).map { "retrying in \($0)" }
    }

    private weak var store: AccountStore?
    private var pollTask: Task<Void, Never>?
    /// Held for the life of the app; the tokens exist only to keep the
    /// observations alive.
    private var observers: [NSObjectProtocol] = []

    func start(store: AccountStore) {
        self.store = store
        observeSleepWake()
        resume()
    }

    /// Opening the popover asks for a reading, but never one that would spend a
    /// request the server has already told us to hold back.
    func refreshIfStale() {
        guard let store else { return }
        guard store.rateLimit == nil || Date() >= nextPollAt else { return }
        let age = store.display.map { Date().timeIntervalSince($0.fetchedAt) }
        if age == nil || age! > Self.popoverStaleAfter {
            Task { await store.refresh() }
        }
    }

    private func resume() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let store = self.store else { return }
                await store.refresh()

                let interval = self.nextInterval(after: store.rateLimit)
                self.nextPollAt = Date().addingTimeInterval(interval.seconds)
                try? await Task.sleep(for: interval, tolerance: self.tolerance)
            }
        }
    }

    private func nextInterval(after rateLimit: AccountStore.RateLimit?) -> Duration {
        let base = ProcessInfo.processInfo.isLowPowerModeEnabled ? lowPowerInterval : normalInterval

        guard let rateLimit else {
            penalty = max(1, penalty / 2)
            return min(base * penalty, maxInterval)
        }

        // Doubling past the cap would not change the interval, but recovery
        // would still have to halve its way back down through those steps.
        if base * penalty < maxInterval { penalty *= 2 }
        let backoff = min(base * penalty, maxInterval)
        guard let retryAfter = rateLimit.retryAfter else { return backoff }
        return max(backoff, .seconds(retryAfter))
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTask?.cancel() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
    }
}

private extension Duration {
    var seconds: TimeInterval { TimeInterval(components.seconds) }
}
