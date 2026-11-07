import Foundation
import HealthKit
import Observation
import WidgetKit

/// The app's single source of weight data: a fast on-disk mirror of Apple Health kept current with an
/// anchored HealthKit query (only changes are fetched after the first sync).
@Observable
final class WeightStore {
    enum Status: Equatable {
        case loading
        case needsAuthorization
        case ready
        case unavailable
        case failed(String)
    }

    enum Mode { case health, demo }

    /// Sorted by date, oldest first.
    private(set) var entries: [WeightEntry] = []
    private(set) var status: Status = .loading
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var series = DerivedSeries.empty
    private(set) var importHistory: [ImportRecord] = []

    let mode: Mode
    @ObservationIgnored private let health = HealthService.shared
    @ObservationIgnored private var byID: [UUID: WeightEntry] = [:]
    @ObservationIgnored private var anchor: HKQueryAnchor?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings, mode: Mode = .health) {
        self.settings = settings
        self.mode = mode
        importHistory = ImportRecord.loadAll()
        if mode == .demo {
            var days = 4 * 365 + 120
            #if DEBUG
            // -demoYears N: a longer demo history for performance testing.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-demoYears"), args.indices.contains(i + 1), let years = Double(args[i + 1]) {
                days = Int(years * 365)
            }
            #endif
            let started = Date.now
            replaceAll(DemoData.entries(days: days))
            #if DEBUG
            print("[perf] demo: \(entries.count) readings, load + series \(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
            #endif
            status = .ready
        } else {
            loadCache()
        }
    }

    var latest: WeightEntry? { entries.last }
    var sources: [String] { Array(Set(entries.map(\.sourceName))).sorted() }

    // MARK: Lifecycle

    func start() async {
        guard mode == .health else { return }
        guard health.isAvailable else { status = .unavailable; return }
        if let unit = await health.preferredUnit() { settings.healthUnit = unit }
        if await health.needsAuthorizationPrompt() {
            status = .needsAuthorization
            return
        }
        startStreaming()
    }

    func connectHealth() async {
        do {
            try await health.requestAuthorization()
            if let unit = await health.preferredUnit() { settings.healthUnit = unit }
            startStreaming()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Restarts the live query (e.g. after returning to the foreground or after an error).
    func resume() {
        guard mode == .health, status != .needsAuthorization, status != .unavailable else { return }
        if streamTask == nil { startStreaming() }
    }

    private func startStreaming() {
        streamTask?.cancel()
        isSyncing = true
        if entries.isEmpty { status = .loading } else { status = .ready }
        streamTask = Task { [weak self, health, anchor] in
            do {
                for try await changes in health.changeStream(since: anchor) {
                    guard let self else { return }
                    self.apply(changes)
                }
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.isSyncing = false
                if self.entries.isEmpty { self.status = .failed(error.localizedDescription) }
            }
            self?.streamTask = nil
        }
    }

    /// One-shot catch-up used by background delivery.
    func refreshOnce() async {
        guard mode == .health else { return }
        do {
            apply(try await health.changes(since: anchor))
        } catch {
            // Health is unavailable while the device is locked; we'll catch up next time.
        }
    }

    private func apply(_ changes: HealthService.Changes) {
        for id in changes.deleted { byID[id] = nil }
        for entry in changes.added { byID[entry.id] = entry }
        anchor = changes.anchor
        rebuildSortedEntries()
        isSyncing = false
        lastSync = .now
        status = .ready
        scheduleCacheSave()
    }

    /// Forgets the local mirror and re-reads everything from Apple Health.
    func rebuildCache() {
        guard mode == .health else { return }
        anchor = nil
        byID = [:]
        entries = []
        try? FileManager.default.removeItem(at: Self.cacheURL)
        startStreaming()
    }

    // MARK: Derived data

    func recomputeSeries() {
        series = DerivedSeries(entries: entries, handling: settings.sameDay, smoothing: settings.trendSmoothing)
        writeWidgetSnapshot()
    }

    private func replaceAll(_ newEntries: [WeightEntry]) {
        byID = Dictionary(newEntries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        rebuildSortedEntries()
    }

    private func rebuildSortedEntries() {
        entries = byID.values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        recomputeSeries()
    }

    // MARK: Editing

    func add(kg: Double, date: Date) async throws {
        if mode == .demo {
            let entry = WeightEntry(date: date, kg: kg, sourceName: "WeightMe", sourceBundleID: health.ownBundleID, isOwn: true)
            byID[entry.id] = entry
            rebuildSortedEntries()
            return
        }
        let entry = try await health.save(kg: kg, date: date)
        byID[entry.id] = entry       // optimistic; the live query will confirm it
        rebuildSortedEntries()
    }

    /// HealthKit samples are immutable, so an edit saves a replacement and then deletes the original.
    func update(_ entry: WeightEntry, kg: Double, date: Date) async throws {
        precondition(entry.isOwn)
        let before = Set(byID.keys)
        try await add(kg: kg, date: date)
        do {
            try await delete(entry)
        } catch {
            // Couldn't remove the original: roll back the replacement so there's no duplicate.
            for id in Set(byID.keys).subtracting(before) {
                if let added = byID[id] { try? await delete(added) }
            }
            throw error
        }
    }

    func delete(_ entry: WeightEntry) async throws {
        guard entry.isOwn else { return }
        if mode == .health { try await health.delete(id: entry.id) }
        byID[entry.id] = nil
        rebuildSortedEntries()
    }

    // MARK: Import

    /// Writes imported readings to Apple Health in chunks, tagging each with `batchID`.
    func importReadings(_ readings: [(date: Date, kg: Double)], batchID: String, sourceLabel: String,
                        fileName: String, progress: @escaping (Double) -> Void) async throws -> Int {
        let chunkSize = 200
        var written = 0
        for start in stride(from: 0, to: readings.count, by: chunkSize) {
            try Task.checkCancellation()
            let chunk = readings[start..<min(start + chunkSize, readings.count)]
            if mode == .demo {
                for r in chunk {
                    let e = WeightEntry(date: r.date, kg: r.kg, sourceName: "WeightMe", sourceBundleID: health.ownBundleID,
                                        isOwn: true, importBatchID: batchID)
                    byID[e.id] = e
                }
            } else {
                let samples = chunk.map {
                    health.makeSample(kg: $0.kg, date: $0.date, metadata: [
                        HKMetadataKeyWasUserEntered: true,
                        WeightMeMetadata.importBatch: batchID,
                        WeightMeMetadata.importSource: sourceLabel,
                    ])
                }
                try await health.save(samples)
                for s in samples { let e = health.entry(from: s); byID[e.id] = e }
            }
            written += chunk.count
            progress(Double(written) / Double(readings.count))
        }
        rebuildSortedEntries()
        let dates = readings.map(\.date)
        let record = ImportRecord(id: batchID, date: .now, fileName: fileName, sourceLabel: sourceLabel,
                                  count: written, firstDate: dates.min(), lastDate: dates.max(), undoneAt: nil)
        importHistory.insert(record, at: 0)
        ImportRecord.saveAll(importHistory)
        return written
    }

    func undoImport(_ record: ImportRecord) async throws -> Int {
        var removed = 0
        if mode == .health {
            removed = try await health.deleteImportBatch(record.id)
        }
        let ids = byID.values.filter { $0.importBatchID == record.id }.map(\.id)
        if mode == .demo { removed = ids.count }
        for id in ids { byID[id] = nil }
        rebuildSortedEntries()
        if let i = importHistory.firstIndex(where: { $0.id == record.id }) {
            importHistory[i].undoneAt = .now
            ImportRecord.saveAll(importHistory)
        }
        return removed
    }

    func entriesInBatch(_ batchID: String) -> Int {
        entries.lazy.filter { $0.importBatchID == batchID }.count
    }

    #if DEBUG
    enum SeedError: LocalizedError {
        case alreadySeeded(Int)
        var errorDescription: String? {
            if case .alreadySeeded(let n) = self { return "Apple Health already has \(n) weights; not seeding again." }
            return nil
        }
    }

    /// Debug: wipe everything this app wrote, seed fresh sample data, and re-read it.
    func reseedHealth() async {
        _ = try? await health.deleteAllOwnSamples()
        try? await seedSampleData(force: true)
        rebuildCache()
    }

    func seedSampleData(force: Bool = false) async throws {
        if !force, entries.count > 100 { throw SeedError.alreadySeeded(entries.count) }
        // Leave today empty so logging a weight is visible as the newest point.
        let demo = DemoData.entries(endingAt: .now).filter { !Calendar.current.isDateInToday($0.date) }
        let samples = demo.map { health.makeSample(kg: $0.kg, date: $0.date, metadata: [HKMetadataKeyWasUserEntered: false]) }
        for start in stride(from: 0, to: samples.count, by: 300) {
            try await health.save(Array(samples[start..<min(start + 300, samples.count)]))
        }
    }

    func deleteAllOwnData() async throws {
        _ = try await health.deleteAllOwnSamples()
    }
    #endif

    // MARK: Cache

    private struct Cache: Codable {
        static let currentVersion = 1
        var version: Int
        var anchor: Data?
        var lastSync: Date?
        var entries: [WeightEntry]
    }

    /// Mirror of the Health data; excluded from backups (see `LocalStorage`).
    static var cacheURL: URL { LocalStorage.appDirectory.appending(path: "weight-cache.json") }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == Cache.currentVersion else { return }
        if let anchorData = cache.anchor {
            anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchorData)
        }
        lastSync = cache.lastSync
        replaceAll(cache.entries)
        if !entries.isEmpty { status = .ready }
    }

    private func scheduleCacheSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let anchorData = self.anchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            let cache = Cache(version: Cache.currentVersion, anchor: anchorData, lastSync: self.lastSync, entries: self.entries)
            guard let data = try? JSONEncoder().encode(cache) else { return }
            let url = Self.cacheURL
            await Task.detached(priority: .utility) { try? LocalStorage.write(data, to: url) }.value
        }
    }

    // MARK: Widget

    private func writeWidgetSnapshot() {
        guard mode == .health || ProcessInfo.processInfo.arguments.contains("-demoWidgets") else { return }
        let snapshot = WidgetSnapshotBuilder.make(series: series, unit: settings.unit, goalKg: settings.goalKg)
        var previous = WidgetSnapshot.load()
        previous?.generatedAt = snapshot.generatedAt   // ignore the timestamp when comparing
        if snapshot != previous {
            try? snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func settingsAffectingWidgetChanged() { writeWidgetSnapshot() }
}

/// All chart series derived from the raw entries. Recomputed only when data or analysis settings change.
struct DerivedSeries {
    var readings: [SeriesPoint]
    var average7: [SeriesPoint]
    var average30: [SeriesPoint]
    var average90: [SeriesPoint]
    var trend: [SeriesPoint]
    var monthly: [MonthlyRange]

    static let empty = DerivedSeries(readings: [], average7: [], average30: [], average90: [], trend: [], monthly: [])

    init(readings: [SeriesPoint], average7: [SeriesPoint], average30: [SeriesPoint], average90: [SeriesPoint],
         trend: [SeriesPoint], monthly: [MonthlyRange]) {
        self.readings = readings; self.average7 = average7; self.average30 = average30
        self.average90 = average90; self.trend = trend; self.monthly = monthly
    }

    init(entries: [WeightEntry], handling: SameDayHandling, smoothing: Double) {
        let readings = Analytics.readings(from: entries, handling: handling)
        self.readings = readings
        average7 = Analytics.rollingAverage(readings, days: 7)
        average30 = Analytics.rollingAverage(readings, days: 30)
        average90 = Analytics.rollingAverage(readings, days: 90)
        trend = Analytics.smoothedTrend(readings, smoothing: smoothing)
        monthly = MonthlyRange.compute(readings)
    }

    func points(for layer: ChartLayer) -> [SeriesPoint] {
        switch layer {
        case .readings: readings
        case .average7: average7
        case .average30: average30
        case .average90: average90
        case .trend: trend
        default: []
        }
    }

    var dateRange: ClosedRange<Date>? {
        guard let first = readings.first?.date, let last = readings.last?.date else { return nil }
        return first...max(last, first.addingTimeInterval(86_400))
    }
}

/// Min / mean / max of one calendar month, for the "Monthly range" layer.
nonisolated struct MonthlyRange: Identifiable, Hashable, Sendable {
    var month: Date
    var minKg: Double
    var maxKg: Double
    var meanKg: Double
    var count: Int
    var id: Date { month }
    var midMonth: Date { month.addingTimeInterval(15 * 86_400) }

    static func compute(_ points: [SeriesPoint], calendar: Calendar = .current) -> [MonthlyRange] {
        var result: [MonthlyRange] = []
        var current: Date?
        var lo = 0.0, hi = 0.0, sum = 0.0, n = 0
        func flush() {
            if let current, n > 0 { result.append(MonthlyRange(month: current, minKg: lo, maxKg: hi, meanKg: sum / Double(n), count: n)) }
        }
        for p in points {
            let month = calendar.dateInterval(of: .month, for: p.date)?.start ?? p.date
            if month != current {
                flush()
                current = month; lo = p.kg; hi = p.kg; sum = 0; n = 0
            }
            lo = min(lo, p.kg); hi = max(hi, p.kg); sum += p.kg; n += 1
        }
        flush()
        return result
    }
}

/// A completed CSV import, kept so it can be reviewed or undone later.
nonisolated struct ImportRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var date: Date
    var fileName: String
    var sourceLabel: String
    var count: Int
    var firstDate: Date?
    var lastDate: Date?
    var undoneAt: Date?

    static func loadAll() -> [ImportRecord] { PrivateData.load().importHistory }

    static func saveAll(_ records: [ImportRecord]) {
        var data = PrivateData.load()
        data.importHistory = records
        data.save()
    }
}

/// Health-related values the user creates (goal weight, import history). Kept in a non-backed-up file
/// rather than UserDefaults, which is included in device backups. Display preferences stay in UserDefaults.
nonisolated struct PrivateData: Codable, Sendable {
    var goalKg: Double?
    var importHistory: [ImportRecord] = []

    static var url: URL { LocalStorage.appDirectory.appending(path: "private-data.json") }

    static func load() -> PrivateData {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(PrivateData.self, from: data) else { return PrivateData() }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? LocalStorage.write(data, to: Self.url)
    }
}
