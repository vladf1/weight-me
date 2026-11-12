import Foundation
import HealthKit
import Testing
@testable import WeightMe

/// Fills or clears a simulator's Apple Health store with sample weights, from outside the app's own code.
///
/// These tests run inside the WeightMe app (it hosts the unit tests), so what they write shows up in Health
/// as WeightMe's data, and they can delete it again. They're skipped unless `SEED_HEALTH` is set — use
/// `Scripts/seed-health.sh`, which sets it. Health access has to be approved once in the app beforehand.
/// "seed", "wipe" or "reseed", from `SEED_HEALTH`.
nonisolated private let seedAction = ProcessInfo.processInfo.environment["SEED_HEALTH"]

@Suite(.serialized, .enabled(if: seedAction != nil, "Run Scripts/seed-health.sh to seed or wipe Health"))
@MainActor
struct HealthSeeding {
    private let health = HealthService.shared

    @Test func run() async throws {
        #expect(HKHealthStore.isHealthDataAvailable())
        try #require(health.canWrite, "WeightMe can't write to Health yet. Open the app in this simulator, tap Connect Apple Health and allow access, then run this again.")

        switch seedAction {
        case "wipe":
            try await wipe()
        case "reseed":
            try await wipe()
            try await seed()
        default:
            // Don't stack a second copy on top of the first; "reseed" replaces it.
            let existing = try await ownWeightCount()
            if existing > 100 {
                print("Already seeded: WeightMe has \(existing) weights in Health. Use reseed to start over.")
                return
            }
            try await seed()
        }
        print("WeightMe now has \(try await ownWeightCount()) weights in Health.")
    }

    private func ownWeightCount() async throws -> Int {
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HealthService.bodyMass, predicate: mine)],
                                            sortDescriptors: [])
        return try await query.result(for: health.store).count
    }

    /// Writes about four years of sample weights, leaving today empty so a newly logged weight
    /// shows up as the newest point.
    private func seed() async throws {
        let entries = DemoData.entries(endingAt: .now).filter { !Calendar.current.isDateInToday($0.date) }
        let samples = entries.map {
            health.makeSample(kg: $0.kg, date: $0.date, metadata: [HKMetadataKeyWasUserEntered: false])
        }
        for start in stride(from: 0, to: samples.count, by: 300) {
            try await health.save(Array(samples[start..<min(start + 300, samples.count)]))
        }
        print("Seeded \(samples.count) weights.")
    }

    /// Deletes every weight WeightMe has written to this simulator's Health store.
    private func wipe() async throws {
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let removed = try await health.store.deleteObjects(of: HealthService.bodyMass, predicate: mine)
        print("Deleted \(removed) weights written by WeightMe.")
    }
}
