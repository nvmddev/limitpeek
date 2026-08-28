import AppKit
import Foundation

/// Decides when to poll: a long interval with generous tolerance, nothing while
/// the machine is asleep, one immediate poll on wake, and a stretched interval
/// in Low Power Mode.
@MainActor
final class Refresher {
    static let popoverStaleAfter: TimeInterval = 10

    private let normalInterval: Duration = .seconds(300)
    private let lowPowerInterval: Duration = .seconds(900)
    private let tolerance: Duration = .seconds(60)

    private weak var store: AccountStore?
    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func start(store: AccountStore) {
        self.store = store
        observeSleepWake()
        resume()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
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
