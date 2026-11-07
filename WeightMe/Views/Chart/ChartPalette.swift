import SwiftUI

enum ChartPalette {
    static let readings = Color.secondary
    static let average7 = Color.blue
    static let average30 = Color.orange
    static let average90 = Color.purple
    static let trend = Color.teal
    static let monthly = Color.indigo
    static let goal = Color.green
    static let projection = Color.teal

    static func color(for layer: ChartLayer) -> Color {
        switch layer {
        case .readings: Color.gray
        case .average7: average7
        case .average30: average30
        case .average90: average90
        case .trend: trend
        case .monthlyRange: monthly
        case .goal: goal
        case .projection: projection
        }
    }
}

/// Nice, human-friendly y-axis bounds and tick marks computed in the display unit.
struct YAxisScale: Equatable {
    var domain: ClosedRange<Double>   // kg
    var ticks: [Double]               // kg
    var decimals: Int

    static func make(minKg: Double, maxKg: Double, unit: WeightUnit, targetTicks: Int = 5) -> YAxisScale {
        var lo = unit.value(fromKilograms: minKg)
        var hi = unit.value(fromKilograms: maxKg)
        let minimumSpan = unit == .pounds ? 3.0 : 1.5
        if hi - lo < minimumSpan {
            let mid = (lo + hi) / 2
            lo = mid - minimumSpan / 2
            hi = mid + minimumSpan / 2
        }
        let pad = (hi - lo) * 0.08
        lo -= pad
        hi += pad
        let step = niceStep(for: hi - lo, targetTicks: targetTicks)
        lo = (lo / step).rounded(.down) * step
        hi = (hi / step).rounded(.up) * step
        var ticks: [Double] = []
        var t = lo
        while t <= hi + step / 2 {
            ticks.append(unit.kilograms(from: t))
            t += step
        }
        let decimals = step < 1 ? (step < 0.5 ? 1 : 1) : 0
        return YAxisScale(domain: unit.kilograms(from: lo)...unit.kilograms(from: hi), ticks: ticks, decimals: decimals)
    }

    static func niceStep(for span: Double, targetTicks: Int) -> Double {
        let raw = span / Double(max(targetTicks, 1))
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let nice: Double = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10
        return nice * magnitude
    }
}
