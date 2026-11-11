import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    enum UnitPreference: String, CaseIterable, Identifiable {
        case health, pounds, kilograms
        var id: String { rawValue }
        var title: String {
            switch self {
            case .health: "Same as Health"
            case .pounds: "Pounds"
            case .kilograms: "Kilograms"
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Unit Apple Health is set to show — filled in at launch.
    var healthUnit: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms

    var unitPreference: UnitPreference { didSet { defaults.set(unitPreference.rawValue, forKey: Keys.unit) } }
    /// Health-related, so stored in the non-backed-up `PrivateData` file, not UserDefaults.
    var goalKg: Double? {
        didSet {
            var data = PrivateData.load()
            data.goalKg = goalKg
            data.save()
        }
    }
    var sameDay: SameDayHandling { didSet { defaults.set(sameDay.rawValue, forKey: Keys.sameDay) } }
    /// Fraction the smoothed trend moves toward each day's weight (Hacker's Diet uses 0.1).
    var trendSmoothing: Double { didSet { defaults.set(trendSmoothing, forKey: Keys.smoothing) } }
    /// How many days of trend data the projection's rate is computed from.
    var projectionWindowDays: Int { didSet { defaults.set(projectionWindowDays, forKey: Keys.projectionWindow) } }

    // Chart layers
    var chartRange: ChartRange { didSet { defaults.set(chartRange.rawValue, forKey: Keys.range) } }
    var visibleLayers: Set<ChartLayer> {
        didSet { defaults.set(visibleLayers.map(\.rawValue), forKey: Keys.layers) }
    }

    var unit: WeightUnit {
        switch unitPreference {
        case .health: healthUnit
        case .pounds: .pounds
        case .kilograms: .kilograms
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unitPreference = UnitPreference(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .health
        goalKg = PrivateData.load().goalKg
        #if DEBUG
        // `-goalKg 80` on the command line (screenshots) overrides it for one launch without saving.
        if let override = defaults.volatileDomain(forName: UserDefaults.argumentDomain)[Keys.goal] as? String {
            goalKg = Double(override)
        }
        #endif
        sameDay = SameDayHandling(rawValue: defaults.string(forKey: Keys.sameDay) ?? "") ?? .all
        trendSmoothing = defaults.object(forKey: Keys.smoothing) as? Double ?? 0.1
        projectionWindowDays = defaults.object(forKey: Keys.projectionWindow) as? Int ?? 30
        chartRange = ChartRange(rawValue: defaults.string(forKey: Keys.range) ?? "") ?? .threeMonths
        if let stored = defaults.stringArray(forKey: Keys.layers) {
            visibleLayers = Set(stored.compactMap(ChartLayer.init(rawValue:)))
        } else {
            visibleLayers = [.readings, .goal]
        }
    }

    func isVisible(_ layer: ChartLayer) -> Bool { visibleLayers.contains(layer) }

    func toggle(_ layer: ChartLayer) {
        if visibleLayers.contains(layer) { visibleLayers.remove(layer) } else { visibleLayers.insert(layer) }
    }

    private enum Keys {
        static let unit = "unitPreference"
        static let goal = "goalKg"
        static let sameDay = "sameDayHandling"
        static let smoothing = "trendSmoothing"
        static let projectionWindow = "projectionWindowDays"
        static let range = "chartRange"
        // v2: the default changed to entries + goal; older saved choices are dropped once.
        static let layers = "chartLayers.v2"
    }
}

/// Preset visible time spans for the chart.
nonisolated enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "Y"
    case twoYears = "2Y"
    case all = "All"

    var id: String { rawValue }

    /// Visible length in days (nil = everything).
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 31
        case .threeMonths: 92
        case .sixMonths: 183
        case .year: 365
        case .twoYears: 730
        case .all: nil
        }
    }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .year: "Year"
        case .twoYears: "2 Years"
        case .all: "All Time"
        }
    }
}

/// Things that can be drawn on the chart.
nonisolated enum ChartLayer: String, CaseIterable, Identifiable, Sendable {
    case readings
    case average7
    case average30
    case average90
    case trend
    case monthlyRange
    case goal
    case projection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readings: "Readings"
        case .average7: "7-day avg"
        case .average30: "30-day avg"
        case .average90: "90-day avg"
        case .trend: "Trend"
        case .monthlyRange: "Monthly range"
        case .goal: "Goal"
        case .projection: "Projection"
        }
    }

    var rollingDays: Int? {
        switch self {
        case .average7: 7
        case .average30: 30
        case .average90: 90
        default: nil
        }
    }
}
