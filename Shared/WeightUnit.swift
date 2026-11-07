import Foundation

/// Display / entry unit. Everything is stored internally in kilograms (HealthKit's canonical mass unit).
nonisolated enum WeightUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case pounds = "lb"
    case kilograms = "kg"

    var id: String { rawValue }

    static let kilogramsPerPound = 0.45359237

    var symbol: String { rawValue }

    var name: String {
        switch self {
        case .pounds: "Pounds"
        case .kilograms: "Kilograms"
        }
    }

    /// Converts kilograms into this unit.
    func value(fromKilograms kg: Double) -> Double {
        switch self {
        case .kilograms: kg
        case .pounds: kg / Self.kilogramsPerPound
        }
    }

    /// Converts a value expressed in this unit into kilograms.
    func kilograms(from value: Double) -> Double {
        switch self {
        case .kilograms: value
        case .pounds: value * Self.kilogramsPerPound
        }
    }

    /// "182.4 lb"
    func format(_ kg: Double, decimals: Int = 1, includeUnit: Bool = true) -> String {
        let number = value(fromKilograms: kg).formatted(.number.precision(.fractionLength(decimals)))
        return includeUnit ? "\(number) \(symbol)" : number
    }

    /// "+1.2 lb" / "−0.8 lb" (true minus sign), "0.0 lb" for no change.
    func formatDelta(_ kg: Double, decimals: Int = 1, includeUnit: Bool = true) -> String {
        let v = value(fromKilograms: kg)
        let rounded = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(decimals)))
        let sign = rounded > 0 ? "+" : (rounded < 0 ? "−" : "")
        return includeUnit ? "\(sign)\(magnitude) \(symbol)" : "\(sign)\(magnitude)"
    }

    /// Plausible human body-weight range used for validation.
    static let plausibleKilograms: ClosedRange<Double> = 20...320
}
