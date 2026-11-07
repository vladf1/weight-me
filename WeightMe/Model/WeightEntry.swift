import Foundation

/// One body-mass reading, mirrored from Apple Health.
nonisolated struct WeightEntry: Identifiable, Hashable, Codable, Sendable {
    /// The HealthKit sample UUID.
    let id: UUID
    let date: Date
    let kg: Double
    let sourceName: String
    let sourceBundleID: String
    /// True when this app wrote the sample (and therefore may edit/delete it).
    let isOwn: Bool
    /// Set for samples written by a CSV import — lets an import be undone as a unit.
    let importBatchID: String?

    init(id: UUID = UUID(), date: Date, kg: Double, sourceName: String, sourceBundleID: String,
         isOwn: Bool, importBatchID: String? = nil) {
        self.id = id
        self.date = date
        self.kg = kg
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.isOwn = isOwn
        self.importBatchID = importBatchID
    }
}

/// How several readings on the same calendar day are treated by the chart and statistics.
nonisolated enum SameDayHandling: String, CaseIterable, Codable, Identifiable, Sendable {
    case all
    case average
    case first
    case lowest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Every reading"
        case .average: "Daily average"
        case .first: "First of the day"
        case .lowest: "Lowest of the day"
        }
    }

    var detail: String {
        switch self {
        case .all: "Plot every reading as recorded in Apple Health."
        case .average: "Combine each day's readings into their average."
        case .first: "Use only the earliest reading each day (morning weight)."
        case .lowest: "Use only the lowest reading each day."
        }
    }
}

/// Metadata keys written into HealthKit samples created by this app.
nonisolated enum WeightMeMetadata {
    static let importBatch = "WeightMeImportBatch"
    static let importSource = "WeightMeImportSource"
}
