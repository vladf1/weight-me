import Foundation
import HealthKit

/// Thin async wrapper around HealthKit for body-mass samples.
nonisolated final class HealthService: @unchecked Sendable {
    static let shared = HealthService()

    let store = HKHealthStore()
    static let bodyMass = HKQuantityType(.bodyMass)
    private static let kilograms = HKUnit.gramUnit(with: .kilo)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var ownBundleID: String { Bundle.main.bundleIdentifier ?? "me.fridman.weightme" }

    // MARK: Authorization

    /// Whether the system still needs to show the permission sheet.
    func needsAuthorizationPrompt() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [Self.bodyMass], read: [Self.bodyMass])
        // Ask unless HealthKit says it's already settled: a fresh device can answer .unknown, and
        // skipping the prompt then leaves every write failing with "authorization not determined".
        return status != .unnecessary
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [Self.bodyMass], read: [Self.bodyMass])
    }

    /// Write permission is knowable; read permission is deliberately hidden by HealthKit.
    var canWrite: Bool { store.authorizationStatus(for: Self.bodyMass) == .sharingAuthorized }

    func preferredUnit() async -> WeightUnit? {
        guard let units = try? await store.preferredUnits(for: [Self.bodyMass]),
              let unit = units[Self.bodyMass] else { return nil }
        if unit == HKUnit.pound() || unit == HKUnit.stone() { return .pounds }
        if unit == Self.kilograms || unit == HKUnit.gram() { return .kilograms }
        return nil
    }

    // MARK: Reading

    struct Changes: Sendable {
        var added: [WeightEntry]
        var deleted: [UUID]
        var anchor: HKQueryAnchor
    }

    /// Everything that changed since `anchor` (everything, when `anchor` is nil).
    func changes(since anchor: HKQueryAnchor?) async throws -> Changes {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        return Changes(added: result.addedSamples.map(entry(from:)),
                       deleted: result.deletedObjects.map(\.uuid),
                       anchor: result.newAnchor)
    }

    /// Long-running stream of changes after `anchor`. The first element contains the initial batch.
    func changeStream(since anchor: HKQueryAnchor?) -> AsyncThrowingStream<Changes, Error> {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass)],
            anchor: anchor
        )
        let store = self.store
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await result in descriptor.results(for: store) {
                        continuation.yield(Changes(added: result.addedSamples.map(self.entry(from:)),
                                                   deleted: result.deletedObjects.map(\.uuid),
                                                   anchor: result.newAnchor))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Readings in a date window — used by background refresh and intents without the full cache.
    func entries(from start: Date, to end: Date = .distantFuture) async throws -> [WeightEntry] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try await descriptor.result(for: store).map(entry(from:))
    }

    func entry(from sample: HKQuantitySample) -> WeightEntry {
        let source = sample.sourceRevision.source
        return WeightEntry(
            id: sample.uuid,
            date: sample.startDate,
            kg: sample.quantity.doubleValue(for: Self.kilograms),
            sourceName: source.name,
            sourceBundleID: source.bundleIdentifier,
            isOwn: isOwnSource(source.bundleIdentifier),
            importBatchID: sample.metadata?[WeightMeMetadata.importBatch] as? String
        )
    }

    // MARK: Writing

    func makeSample(kg: Double, date: Date, metadata: [String: Any] = [:]) -> HKQuantitySample {
        HKQuantitySample(type: Self.bodyMass,
                         quantity: HKQuantity(unit: Self.kilograms, doubleValue: kg),
                         start: date, end: date, metadata: metadata.isEmpty ? nil : metadata)
    }

    @discardableResult
    func save(kg: Double, date: Date, userEntered: Bool = true) async throws -> WeightEntry {
        let sample = makeSample(kg: kg, date: date, metadata: [HKMetadataKeyWasUserEntered: userEntered])
        try await store.save(sample)
        return entry(from: sample)
    }

    func save(_ samples: [HKQuantitySample]) async throws {
        guard !samples.isEmpty else { return }
        try await store.save(samples)
    }

    /// Deletes one sample this app wrote. HealthKit silently refuses to delete other apps' samples.
    /// The iPhone app or its watch app (me.fridman.weightme.watchkitapp).
    func isOwnSource(_ bundleID: String) -> Bool {
        bundleID == ownBundleID || bundleID.hasPrefix(ownBundleID + ".")
    }

    enum DeleteError: LocalizedError {
        case notAllowed
        var errorDescription: String? {
            "Apple Health didn't let WeightMe delete this entry. Delete it on the device that logged it, or in the Health app."
        }
    }

    /// Deletes one sample WeightMe wrote. HealthKit only lets an app delete its own samples (and may treat
    /// entries logged on the watch as the watch app's), so a delete that removes nothing is an error.
    func delete(id: UUID) async throws {
        let removed = try await store.deleteObjects(of: Self.bodyMass, predicate: HKQuery.predicateForObject(with: id))
        if removed == 0 { throw DeleteError.notAllowed }
    }

    /// Deletes every sample written by one CSV import. Returns how many were removed.
    func deleteImportBatch(_ batchID: String) async throws -> Int {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: WeightMeMetadata.importBatch,
                                                    allowedValues: [batchID])
        return try await store.deleteObjects(of: Self.bodyMass, predicate: predicate)
    }

    // MARK: Background delivery

    /// Wakes the app when weight data changes in Health so the widget stays current.
    func enableBackgroundDelivery(onChange: @escaping @Sendable () async -> Void) {
        guard isAvailable else { return }
        let query = HKObserverQuery(sampleType: Self.bodyMass, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            let done = UncheckedCompletion(call: completion)
            Task {
                await onChange()
                done.call()
            }
        }
        store.execute(query)
        Task { try? await store.enableBackgroundDelivery(for: Self.bodyMass, frequency: .immediate) }
    }
}

/// HealthKit's observer completion handler isn't annotated Sendable; it is safe to call from any thread.
private nonisolated struct UncheckedCompletion: @unchecked Sendable {
    let call: () -> Void
}
