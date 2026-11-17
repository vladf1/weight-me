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

    @Test func exportWeightHistoryReturnsAFileWeightMeCanRestore() async throws {
        let store = try store
        var intent = ExportWeightHistoryIntent()
        intent.unit = .kilograms
        intent.includeOtherApps = true
        let file = try #require(try await intent.perform().value)
        #expect(file.filename == CSVExport.fileName())
        let parsed = try WeightCSVImport.parse(try #require(CSV.decode(file.data)))
        #expect(parsed.format == .weightMe)
        #expect(parsed.rows.count == store.entries.count)
        #expect(parsed.rows.allSatisfy { $0.unit == .kilograms })
        // Everything in the file is already in Health, so restoring it would add nothing.
        let plan = ImportPlan.build(file: parsed, unit: .kilograms, defaultHour: 8, defaultMinute: 0, existing: store.entries)
        #expect(plan.importCount == 0)
    }

    @Test func exportWeightHistoryCanLeaveOutOtherApps() async throws {
        let store = try store
        var intent = ExportWeightHistoryIntent()
        intent.unit = nil
        intent.includeOtherApps = false
        let own = store.entries.filter(\.isOwn).count
        if own == 0 {
            await #expect(throws: WeightIntentError.self) { _ = try await intent.perform() }
        } else {
            let file = try #require(try await intent.perform().value)
            #expect(try WeightCSVImport.parse(try #require(CSV.decode(file.data))).rows.count == own)
        }
    }
}

/// App Store Connect rejects uploads whose App Intent descriptions contain "Apple" (error 90626).
struct IntentMetadataTests {
    @Test func descriptionsDontMentionApple() {
        let descriptions = [LogWeightIntent.description, GetLatestWeightIntent.description, OpenLogWeightIntent.description,
                            ExportWeightHistoryIntent.description]
        for description in descriptions {
            let text = String(localized: description.descriptionText)
            #expect(!text.localizedCaseInsensitiveContains("apple"), "\(text)")
        }
    }
}
