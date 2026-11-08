import AppKit
import Foundation
import Observation

/// Decides when to poll: paused while signed out or reauthenticating, paused
/// while the machine sleeps, stretched in Low Power Mode.
@MainActor
@Observable
final class Refresher {
    static let popoverStaleAfter: TimeInterval = 60

    private let tolerance: Duration = .seconds(15)
    private var schedule = PollSchedule()
    private(set) var nextPollAt = Date.distantPast

    private static let countdownFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()

    var retryCountdown: String? {
        guard let store, store.rateLimit != nil else { return nil }
        let target = max(nextPollAt, store.rateLimit?.deadline ?? .distantPast)
        let seconds = target.timeIntervalSinceNow
        guard seconds >= 1 else { return nil }
        return Self.countdownFormatter.string(from: seconds).map { "retrying in \($0)" }
    }

    private weak var store: AccountStore?
    private var pollTask: Task<Void, Never>?
    /// Distinguishes the current loop from one that is still unwinding.
    private var loopGeneration = 0
    private var started = false
    /// Kept for the life of the app so the observers stay registered.
    private var observers: [NSObjectProtocol] = []

    func start(store: AccountStore) {
        guard !started else { return }
        started = true
        self.store = store
        store.onSessionStateChange = { [weak self] state in
            self?.handleSessionState(state)
        }
        observeSleepWake()
        switch store.sessionState {
        case .signedIn:
            resume(immediately: true)
        case .signedOut, .reauthenticationRequired:
            pause()
        }
    }

    /// Opening the popover asks for a reading, but never one that would spend a
    /// request the server has already told us to hold back.
    func refreshIfStale() {
        guard let store, store.sessionState == .signedIn else { return }
        if let deadline = store.rateLimit?.deadline, Date() < deadline { return }
        if let fetchedAt = store.display?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) <= Self.popoverStaleAfter { return }
        Task { await store.refresh() }
    }

    private func handleSessionState(_ state: AccountStore.SessionState) {
        switch state {
        case .signedIn:
            // Sign-in has already fetched a reading; wait a full interval.
            resume(immediately: false)
        case .signedOut, .reauthenticationRequired:
            pause()
        }
    }

    private func resume(immediately: Bool) {
        guard let store, store.sessionState == .signedIn else {
            pause()
            return
        }
        pollTask?.cancel()
        loopGeneration += 1
        let generation = loopGeneration
        let now = Date()
        if immediately {
            nextPollAt = now
        } else {
            let base: TimeInterval = store.display == nil || store.lastError != nil
                ? AccountStore.minRefreshInterval
                : PollSchedule.normalInterval
            let deadline = store.rateLimit?.deadline ?? .distantPast
            nextPollAt = max(now.addingTimeInterval(base), deadline)
        }
        pollTask = Task { [weak self] in
            await self?.pollLoop(immediately: immediately, generation: generation)
        }
    }

    /// Stops polling without scheduling a no-op wake-up later. The next
    /// sign-in or wake starts a fresh loop.
    private func pause() {
        loopGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        nextPollAt = .distantPast
    }

    private func pollLoop(immediately: Bool, generation: Int) async {
        var firstRun = immediately
        while !Task.isCancelled, generation == loopGeneration {
            guard let store, store.sessionState == .signedIn else {
                finish(generation)
                return
            }
            if !firstRun {
                let wait = max(nextPollAt.timeIntervalSinceNow, 1)
                do {
                    try await Task.sleep(for: .seconds(wait), tolerance: tolerance)
                } catch {
                    return
                }
                guard !Task.isCancelled, generation == loopGeneration else { return }
                guard store.sessionState == .signedIn else {
                    finish(generation)
                    return
                }
            }
            firstRun = false

            let outcome = await store.refresh()
            guard !Task.isCancelled, generation == loopGeneration else { return }
            switch outcome {
            case .signedOut, .requiresReauthentication:
                finish(generation)
                return
            case .updated, .rateLimited, .failed, .skipped:
                break
            }

            let delay = schedule.nextDelay(
                after: outcome,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
            scheduleNextPoll(after: outcome, delay: delay, store: store)
        }
    }

    /// Ends the current loop; only the loop that is still current may do so.
    private func finish(_ generation: Int) {
        guard generation == loopGeneration else { return }
        loopGeneration += 1
        pollTask = nil
        nextPollAt = .distantPast
    }

    private func scheduleNextPoll(after outcome: AccountStore.RefreshOutcome,
                                  delay: TimeInterval,
                                  store: AccountStore) {
        let now = Date()
        if case .skipped = outcome {
            if let deadline = store.rateLimit?.deadline, deadline > now {
                nextPollAt = deadline
            } else {
                nextPollAt = now.addingTimeInterval(AccountStore.minRefreshInterval)
            }
            return
        }
        let deadline = store.rateLimit?.deadline ?? .distantPast
        nextPollAt = max(now.addingTimeInterval(delay), deadline)
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.store?.sessionState == .signedIn else { return }
                self.resume(immediately: true)
            }
        })
    }
}

/// How long to wait before the next request. Separated so the backoff can be
/// tested without timers or network.
struct PollSchedule: Sendable {
    static let normalInterval: TimeInterval = 180
    static let lowPowerInterval: TimeInterval = 300
    static let maximumInterval: TimeInterval = AccountStore.rateLimitFallback

    /// Doubles on a 429 and halves after a clean poll. One doubling reaches the
    /// five-minute cap.
    private(set) var penalty = 1

    mutating func nextDelay(after outcome: AccountStore.RefreshOutcome,
                            isLowPowerMode: Bool) -> TimeInterval {
        let base = isLowPowerMode ? Self.lowPowerInterval : Self.normalInterval

        switch outcome {
        case .updated:
            penalty = max(1, penalty / 2)
        case .rateLimited(let retryAfter):
            if base * Double(penalty) < Self.maximumInterval { penalty *= 2 }
            let backoff = min(base * Double(penalty), Self.maximumInterval)
            let requested = min(max(retryAfter ?? 0, 0), API.maximumRetryAfter)
            return max(backoff, requested)
        case .failed, .skipped, .signedOut, .requiresReauthentication:
            break
        }
        return min(base * Double(penalty), Self.maximumInterval)
    }
}
