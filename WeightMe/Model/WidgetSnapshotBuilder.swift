import Foundation

enum WidgetSnapshotBuilder {
    static func make(series: DerivedSeries, unit: WeightUnit, goalKg: Double?, now: Date = .now) -> WidgetSnapshot {
        let cutoff = now.addingTimeInterval(-92 * 86_400)
        let recentTrend = series.trend.filter { $0.date >= cutoff }
        let recentReadings = series.readings.filter { $0.date >= cutoff }

        var change30: Double?
        var weekly: Double?
        if let lastTrend = series.trend.last {
            let monthAgo = lastTrend.date.addingTimeInterval(-30 * 86_400)
            if let past = Analytics.value(series.trend, at: monthAgo, tolerance: 4 * 86_400) {
                change30 = lastTrend.kg - past.kg
            }
            let window = Analytics.slice(series.trend, in: monthAgo...lastTrend.date)
            weekly = Analytics.linearRegression(window).map { $0.slope * 7 }
        }

        return WidgetSnapshot(
            generatedAt: now,
            unit: unit,
            latestDate: series.readings.last?.date,
            latestKg: series.readings.last?.kg,
            trendKg: series.trend.last?.kg,
            change30DaysKg: change30,
            weeklyRateKg: weekly,
            goalKg: goalKg,
            trend: recentTrend.map { .init(date: $0.date, kg: $0.kg) },
            readings: recentReadings.map { .init(date: $0.date, kg: $0.kg) }
        )
    }
}
