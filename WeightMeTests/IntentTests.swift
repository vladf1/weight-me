import Foundation
import Testing
@testable import WeightMe

/// Siri / Shortcuts actions, run against the test host's demo store (no HealthKit).
@MainActor
@Suite(.serialized)
struct IntentTests {
    var store: WeightStore {
        get throws { try #require(AppDependencies.shared.store, "test host should create the store") }
    }

    @Test func logWeightAddsAnEntry() async throws {
        let store = try store
        let before = store.entries.count
        var intent = LogWeightIntent()
        intent.weight = Measurement(value: 178.6, unit: .pounds)
        intent.date = nil
        _ = try await intent.perform()
        #expect(store.entries.count == before + 1)
        let latest = try #require(store.latest)
        #expect(abs(WeightUnit.pounds.value(fromKilograms: latest.kg) - 178.6) < 0.01)
        #expect(abs(latest.date.timeIntervalSinceNow) < 60)
        try await store.delete(latest)
    }

    @Test func logWeightAcceptsKilograms() async throws {
        let store = try store
        var intent = LogWeightIntent()
        intent.weight = Measurement(value: 81.2, unit: .kilograms)
        _ = try await intent.perform()
        let latest = try #require(store.latest)
        #expect(abs(latest.kg - 81.2) < 0.001)
        try await store.delete(latest)
    }

    @Test func logWeightRejectsImplausibleValues() async throws {
        let store = try store
        let before = store.entries.count
        var intent = LogWeightIntent()
        intent.weight = Measurement(value: 1800, unit: .pounds)   // e.g. a misheard "180.0"
        await #expect(throws: WeightIntentError.self) { _ = try await intent.perform() }
        #expect(store.entries.count == before)
    }

    @Test func logWeightNeverWritesFutureDates() async throws {
        let store = try store
        var intent = LogWeightIntent()
        intent.weight = Measurement(value: 180, unit: .pounds)
        intent.date = .now.addingTimeInterval(3 * 86_400)
        _ = try await intent.perform()
        let latest = try #require(store.latest)
        #expect(latest.date <= .now)
        try await store.delete(latest)
    }

    @Test func getLatestWeightSucceedsWithData() async throws {
        _ = try store
        _ = try await GetLatestWeightIntent().perform()
    }
}
