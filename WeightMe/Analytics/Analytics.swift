import Foundation

/// A single point in a plotted series. `segment` breaks lines across long gaps in the data.
nonisolated struct SeriesPoint: Identifiable, Hashable, Sendable {
    var date: Date
    var kg: Double
    var segment: Int = 0
    var id: Date { date }
}

nonisolated struct RegressionLine: Sendable, Equatable {
    /// kg per day
    var slope: Double
    /// kg at `origin`
    var intercept: Double
    var origin: Date

    func value(at date: Date) -> Double {
        intercept + slope * date.timeIntervalSince(origin) / 86_400
    }

    /// The date at which the line reaches `kg`, if it is heading toward it.
    func date(reaching kg: Double, after start: Date) -> Date? {
        guard slope != 0 else { return nil }
        let days = (kg - intercept) / slope
        let date = origin.addingTimeInterval(days * 86_400)
        return date > start ? date : nil
    }
}

nonisolated struct RangeStats: Sendable, Equatable {
    var count: Int
    var first: SeriesPoint
    var last: SeriesPoint
    var minimum: SeriesPoint
    var maximum: SeriesPoint
    var mean: Double
    /// Change between the trend values at the start and end of the range (falls back to raw readings).
    var change: Double
    /// kg per week, from a least-squares fit over the range.
    var weeklyRate: Double?
}

/// Pure functions that turn raw readings into chartable series. All inputs must be sorted by date.
nonisolated enum Analytics {

    // MARK: Same-day handling

    static func readings(from entries: [WeightEntry], handling: SameDayHandling,
                         calendar: Calendar = .current) -> [SeriesPoint] {
        switch handling {
        case .all:
            return entries.map { SeriesPoint(date: $0.date, kg: $0.kg) }
        case .average, .first, .lowest:
            var result: [SeriesPoint] = []
            var dayStart: Date?
            var bucket: [WeightEntry] = []
            func flush() {
                guard let first = bucket.first else { return }
                switch handling {
                case .average:
                    let mean = bucket.map(\.kg).reduce(0, +) / Double(bucket.count)
                    let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: first.date) ?? first.date
                    result.append(SeriesPoint(date: bucket.count == 1 ? first.date : noon, kg: mean))
                case .first:
                    result.append(SeriesPoint(date: first.date, kg: first.kg))
                case .lowest:
                    let low = bucket.min { $0.kg < $1.kg }!
                    result.append(SeriesPoint(date: low.date, kg: low.kg))
                case .all:
                    break
                }
                bucket.removeAll(keepingCapacity: true)
            }
            for entry in entries {
                let start = calendar.startOfDay(for: entry.date)
                if start != dayStart {
                    flush()
                    dayStart = start
                }
                bucket.append(entry)
            }
            flush()
            return result
        }
    }

    /// One value per calendar day that has data (the mean of that day's readings), stamped at noon.
    static func dailyMeans(_ points: [SeriesPoint], calendar: Calendar = .current) -> [SeriesPoint] {
        var result: [SeriesPoint] = []
        var currentDay: Date?
        var sum = 0.0
        var n = 0
        for p in points {
            let day = calendar.startOfDay(for: p.date)
            if day != currentDay {
                if let d = currentDay, n > 0 {
                    result.append(SeriesPoint(date: d.addingTimeInterval(12 * 3600), kg: sum / Double(n)))
                }
                currentDay = day
                sum = 0
                n = 0
            }
            sum += p.kg
            n += 1
        }
        if let d = currentDay, n > 0 {
            result.append(SeriesPoint(date: d.addingTimeInterval(12 * 3600), kg: sum / Double(n)))
        }
        return result
    }

    // MARK: Moving averages

    /// Trailing, time-based moving average: at each day with data, the mean of all readings in the
    /// preceding `days` days (inclusive). Lines are broken (new `segment`) where the gap between
    /// readings exceeds the window, so the chart never draws an "average" across months of no data.
    static func rollingAverage(_ points: [SeriesPoint], days: Int, calendar: Calendar = .current) -> [SeriesPoint] {
        guard !points.isEmpty else { return [] }
        let daily = dailyMeans(points, calendar: calendar)
        let window = TimeInterval(days) * 86_400
        var result: [SeriesPoint] = []
        result.reserveCapacity(daily.count)
        var lo = 0          // index into points (raw readings)
        var hi = 0
        var sum = 0.0
        var segment = 0
        var previous: Date?
        for day in daily {
            let end = calendar.startOfDay(for: day.date).addingTimeInterval(86_400)  // exclusive
            let start = end.addingTimeInterval(-window)
            while hi < points.count, points[hi].date < end { sum += points[hi].kg; hi += 1 }
            while lo < hi, points[lo].date < start { sum -= points[lo].kg; lo += 1 }
            let n = hi - lo
            guard n > 0 else { continue }
            if let previous, day.date.timeIntervalSince(previous) > max(window, 3 * 86_400) { segment += 1 }
            previous = day.date
            result.append(SeriesPoint(date: day.date, kg: sum / Double(n), segment: segment))
        }
        return result
    }

    /// Mean and count of the readings in the `days` calendar days ending on the day of the latest
    /// reading — the same window as the last point of `rollingAverage`.
    static func recentAverage(_ points: [SeriesPoint], days: Int,
                              calendar: Calendar = .current) -> (kg: Double, count: Int)? {
        guard let last = points.last else { return nil }
        let end = calendar.startOfDay(for: last.date).addingTimeInterval(86_400)
        let start = end.addingTimeInterval(-TimeInterval(days) * 86_400)
        let window = points.reversed().prefix { $0.date >= start }
        guard !window.isEmpty else { return nil }
        return (window.reduce(0) { $0 + $1.kg } / Double(window.count), window.count)
    }

    /// Exponentially smoothed trend in the style of The Hacker's Diet: each day the trend moves
    /// `smoothing` (default 10%) of the way toward that day's weight. Days without readings are
    /// linearly interpolated so gaps don't distort the smoothing; gaps longer than `maxGapDays`
    /// restart the trend (new segment) at the next reading.
    static func smoothedTrend(_ points: [SeriesPoint], smoothing: Double = 0.1, maxGapDays: Int = 45,
                              calendar: Calendar = .current) -> [SeriesPoint] {
        let daily = dailyMeans(points, calendar: calendar)
        guard var previous = daily.first else { return [] }
        var trend = previous.kg
        var segment = 0
        var result = [SeriesPoint(date: previous.date, kg: trend, segment: segment)]
        result.reserveCapacity(daily.count * 2)
        for point in daily.dropFirst() {
            let gapDays = Int((point.date.timeIntervalSince(previous.date) / 86_400).rounded())
            if gapDays > maxGapDays {
                segment += 1
                trend = point.kg
                result.append(SeriesPoint(date: point.date, kg: trend, segment: segment))
            } else {
                for step in 1...max(gapDays, 1) {
                    let fraction = Double(step) / Double(max(gapDays, 1))
                    let interpolated = previous.kg + (point.kg - previous.kg) * fraction
                    trend += smoothing * (interpolated - trend)
                    if step == max(gapDays, 1) {
                        result.append(SeriesPoint(date: point.date, kg: trend, segment: segment))
                    }
                }
            }
            previous = point
        }
        return result
    }

    // MARK: Regression & stats

    static func linearRegression(_ points: some Collection<SeriesPoint>) -> RegressionLine? {
        guard points.count >= 2, let origin = points.first?.date else { return nil }
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for p in points {
            let x = p.date.timeIntervalSince(origin) / 86_400
            sx += x; sy += p.kg; sxx += x * x; sxy += x * p.kg
        }
        let n = Double(points.count)
        let denominator = n * sxx - sx * sx
        guard abs(denominator) > 1e-9 else { return nil }
        let slope = (n * sxy - sx * sy) / denominator
        let intercept = (sy - slope * sx) / n
        return RegressionLine(slope: slope, intercept: intercept, origin: origin)
    }

    /// Statistics for the points inside `range`. `trend` (optional) is used for a less noisy "change".
    static func stats(readings: [SeriesPoint], trend: [SeriesPoint], in range: ClosedRange<Date>) -> RangeStats? {
        let slice = Self.slice(readings, in: range)
        guard let first = slice.first, let last = slice.last else { return nil }
        var minimum = first, maximum = first, sum = 0.0
        for p in slice {
            if p.kg < minimum.kg { minimum = p }
            if p.kg > maximum.kg { maximum = p }
            sum += p.kg
        }
        let trendSlice = Self.slice(trend, in: range)
        let change: Double
        if let tf = trendSlice.first, let tl = trendSlice.last, trendSlice.count >= 2 {
            change = tl.kg - tf.kg
        } else {
            change = last.kg - first.kg
        }
        let span = last.date.timeIntervalSince(first.date)
        let rate = span >= 6 * 86_400 ? linearRegression(slice).map { $0.slope * 7 } : nil
        return RangeStats(count: slice.count, first: first, last: last, minimum: minimum, maximum: maximum,
                          mean: sum / Double(slice.count), change: change, weeklyRate: rate)
    }

    /// Binary-searched sub-range of a date-sorted array.
    static func slice(_ points: [SeriesPoint], in range: ClosedRange<Date>) -> ArraySlice<SeriesPoint> {
        let lower = lowerBound(points, range.lowerBound)
        var upper = lowerBound(points, range.upperBound)
        while upper < points.count, points[upper].date <= range.upperBound { upper += 1 }
        return points[lower..<max(lower, upper)]
    }

    static func lowerBound(_ points: [SeriesPoint], _ date: Date) -> Int {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// The point closest in time to `date`.
    static func nearest(_ points: [SeriesPoint], to date: Date) -> SeriesPoint? {
        guard !points.isEmpty else { return nil }
        let i = lowerBound(points, date)
        let candidates = [i - 1, i].filter { $0 >= 0 && $0 < points.count }.map { points[$0] }
        return candidates.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The most recent point at or before `date` (used to read off an average at a given moment).
    static func value(_ points: [SeriesPoint], at date: Date, tolerance: TimeInterval = 2 * 86_400) -> SeriesPoint? {
        guard let p = nearest(points, to: date), abs(p.date.timeIntervalSince(date)) <= tolerance else { return nil }
        return p
    }
}
