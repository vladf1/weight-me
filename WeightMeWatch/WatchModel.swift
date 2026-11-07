import Foundation
import HealthKit
import Observation

/// The watch talks to Apple Health on the watch directly, so logging works without the phone nearby;
/// Apple syncs the entry to the iPhone's Health (and from there into the WeightMe app) when they connect.
@Observable
final class WatchModel {
    enum State: Equatable {
        case loading
        case needsAuthorization
        case ready
        case unavailable
        case failed(String)
    }

    struct Reading: Equatable {
        var kg: Double
        var date: Date
    }

    private(set) var state: State = .loading
    /// The most recent weight in Apple Health, from any app or scale.
    private(set) var latest: Reading?
    private(set) var unit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private let bodyMass = HKQuantityType(.bodyMass)
    @ObservationIgnored private let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    func start() async {
        if isDemo {
            unit = .pounds
            latest = Reading(kg: WeightUnit.pounds.kilograms(from: 181.4), date: .now.addingTimeInterval(-26 * 3600))
            state = .ready
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        let status = try? await store.statusForAuthorizationRequest(toShare: [bodyMass], read: [bodyMass])
        if status == .shouldRequest {
            state = .needsAuthorization
            return
        }
        await refresh()
    }

    func connect() async {
        do {
            try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Re-reads the unit and the latest weight (e.g. when the app comes back to the foreground).
    func refresh() async {
        guard !isDemo, state != .needsAuthorization, state != .unavailable else { return }
        if let units = try? await store.preferredUnits(for: [bodyMass]), let preferred = units[bodyMass] {
            if preferred == .pound() || preferred == .stone() { unit = .pounds }
            if preferred == .gramUnit(with: .kilo) { unit = .kilograms }
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            if let sample = try await descriptor.result(for: store).first {
                latest = Reading(kg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), date: sample.startDate)
            }
            state = .ready
        } catch {
            // Health data is unavailable while the watch is locked; keep what we have.
            if latest == nil { state = .failed(error.localizedDescription) }
        }
    }

    func log(kg: Double) async throws {
        let now = Date.now
        if !isDemo {
            let sample = HKQuantitySample(
                type: bodyMass,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                start: now, end: now,
                metadata: [HKMetadataKeyWasUserEntered: true]
            )
            try await store.save(sample)
        }
        latest = Reading(kg: kg, date: now)
    }
}
