import AppKit
import Testing
@testable import LimitPeek

/// The cache exists to hand the same `NSImage` object back while the drawn
/// value is unchanged, so these tests use identity rather than pixels and do
/// not depend on a display or a run loop.
@MainActor
@Suite(.serialized)
struct MenuBarLabelCacheTests {
    @Test func sameQuantisedValueReturnsTheSameImage() {
        let cache = makeCache()

        cache.update(percent: 42, style: .both)
        let first = cache.image
        cache.update(percent: 42.2, style: .both)

        #expect(cache.image === first)
    }

    @Test func changedValueReturnsANewImage() {
        let cache = makeCache()

        cache.update(percent: 42, style: .both)
        let first = cache.image
        cache.update(percent: 43, style: .both)

        #expect(cache.image !== first)
    }

    @Test func fractionalValuesRoundToTheSameKey() {
        let cache = makeCache()

        cache.update(percent: 41.4, style: .bar)
        let fortyOne = cache.image
        cache.update(percent: 40.8, style: .bar)
        #expect(cache.image === fortyOne)

        cache.update(percent: 41.6, style: .bar)
        #expect(cache.image !== fortyOne)
    }

    @Test func negativeValuesClampToZero() {
        let cache = makeCache()

        cache.update(percent: -10, style: .bar)
        let clamped = cache.image
        cache.update(percent: 0.4, style: .bar)

        #expect(cache.image === clamped)
    }

    @Test func everythingAboveOneHundredCollapsesToOneKey() {
        let cache = makeCache()

        cache.update(percent: 100.1, style: .both)
        let justOver = cache.image
        cache.update(percent: 100.4, style: .both)
        #expect(cache.image === justOver)

        cache.update(percent: 250, style: .both)
        #expect(cache.image === justOver)

        cache.update(percent: 1_000, style: .both)
        #expect(cache.image === justOver)
    }

    @Test func atOneHundredIsDistinctFromAboveOneHundred() {
        let cache = makeCache()

        cache.update(percent: 100, style: .both)
        let exactlyFull = cache.image
        cache.update(percent: 100.1, style: .both)

        #expect(cache.image !== exactlyFull)
    }

    @Test func styleChangeReturnsANewImage() {
        let cache = makeCache()

        cache.update(percent: 42, style: .both)
        let both = cache.image

        cache.update(percent: 42, style: .percentage)
        let percentage = cache.image
        #expect(percentage !== both)

        cache.update(percent: 42, style: .bar)
        #expect(cache.image !== both)
        #expect(cache.image !== percentage)
    }

    @Test func nilPercentIsDeduplicatedAndDistinctFromZero() {
        let cache = makeCache()

        cache.update(percent: 0, style: .both)
        let zero = cache.image

        cache.update(percent: nil, style: .both)
        let noData = cache.image
        #expect(noData !== zero)

        cache.update(percent: nil, style: .both)
        #expect(cache.image === noData)
    }

    @Test func nonFinitePercentIsTreatedAsZero() {
        let cache = makeCache()

        cache.update(percent: nil, style: .both)
        let noData = cache.image

        cache.update(percent: 0, style: .both)
        let zero = cache.image
        #expect(zero !== noData)

        cache.update(percent: .infinity, style: .both)
        #expect(cache.image === zero)

        cache.update(percent: -.infinity, style: .both)
        #expect(cache.image === zero)

        cache.update(percent: .nan, style: .both)
        #expect(cache.image === zero)
    }

    @Test func styleReturnsAfterAValueChangeRebuilds() {
        let cache = makeCache()

        cache.update(percent: 42, style: .both)
        let initial = cache.image
        cache.update(percent: 43, style: .both)
        let changed = cache.image
        #expect(changed !== initial)

        cache.update(percent: 42, style: .both)
        #expect(cache.image !== changed)
    }

    // MARK: - Helpers

    /// `MenuBarLabelCache` observes `NSApp.effectiveAppearance`, so the shared
    /// application object must exist before the cache is built.
    private func makeCache() -> MenuBarLabelCache {
        _ = NSApplication.shared
        return MenuBarLabelCache()
    }
}
