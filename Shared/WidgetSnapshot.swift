import Foundation

/// A small, precomputed summary the app writes for the widgets so they never need HealthKit access.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    nonisolated struct Point: Codable, Sendable, Equatable, Identifiable {
        var date: Date
        var kg: Double
        var id: Date { date }
    }

    var generatedAt: Date
    var unit: WeightUnit
    var latestDate: Date?
    var latestKg: Double?
    /// Smoothed trend value at the latest reading.
    var trendKg: Double?
    /// Trend change over the last 30 days (negative = losing).
    var change30DaysKg: Double?
    /// Trend rate in kg per week over the last 30 days.
    var weeklyRateKg: Double?
    var goalKg: Double?
    /// Daily trend values, last ~90 days.
    var trend: [Point]
    /// Raw readings, last ~90 days.
    var readings: [Point]

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: SharedStorage.snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: SharedStorage.snapshotURL, options: .atomic)
    }

    /// Plausible sample data for widget previews / gallery.
    static var preview: WidgetSnapshot {
        let now = Date()
        var readings: [Point] = []
        var trend: [Point] = []
        var t = 86.0
        for day in stride(from: 89, through: 0, by: -1) {
            let date = Calendar.current.date(byAdding: .day, value: -day, to: now)!
            let base = 86.0 - Double(89 - day) * 0.035
            let reading = base + sin(Double(day) * 1.3) * 0.45 + cos(Double(day) * 0.7) * 0.3
            t += 0.1 * (reading - t)
            if day % 2 == 0 || day < 10 { readings.append(Point(date: date, kg: reading)) }
            trend.append(Point(date: date, kg: t))
        }
        return WidgetSnapshot(
            generatedAt: now, unit: .pounds,
            latestDate: readings.last?.date, latestKg: readings.last?.kg,
            trendKg: trend.last?.kg, change30DaysKg: -1.05, weeklyRateKg: -0.24,
            goalKg: 80, trend: trend, readings: readings
        )
    }
}
