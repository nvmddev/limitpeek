import AppKit
import Foundation

/// Decides when to poll: slow and tolerant, paused while the machine sleeps,
/// stretched in Low Power Mode.
@MainActor
final class Refresher {
    static let popoverStaleAfter: TimeInterval = 10

    private let normalInterval: Duration = .seconds(300)
    private let lowPowerInterval: Duration = .seconds(900)
    private let tolerance: Duration = .seconds(60)

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

    func refreshIfStale() {
        guard let store else { return }
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

                let interval = ProcessInfo.processInfo.isLowPowerModeEnabled
                    ? self.lowPowerInterval
                    : self.normalInterval
                try? await Task.sleep(for: interval, tolerance: self.tolerance)
            }
        }
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
