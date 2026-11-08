import Foundation
import Testing
@testable import WeightMe

@MainActor
struct AnalyticsTests {
    let calendar = Calendar.current
    let start = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 7))!

    func day(_ n: Int, hour: Int = 7) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)!)!
    }

    func entry(_ n: Int, _ kg: Double, hour: Int = 7) -> WeightEntry {
        WeightEntry(date: day(n, hour: hour), kg: kg, sourceName: "t", sourceBundleID: "t", isOwn: false)
    }

    @Test func sameDayHandling() {
        let entries = [entry(0, 80, hour: 7), entry(0, 82, hour: 21), entry(1, 79)]
        #expect(Analytics.readings(from: entries, handling: .all).count == 3)
        let avg = Analytics.readings(from: entries, handling: .average)
        #expect(avg.map(\.kg) == [81, 79])
        #expect(Analytics.readings(from: entries, handling: .first).map(\.kg) == [80, 79])
        #expect(Analytics.readings(from: entries, handling: .lowest).map(\.kg) == [80, 79])
    }

    @Test func rollingAverageUsesTrailingWindow() {
        let points = (0..<10).map { SeriesPoint(date: day($0), kg: Double($0)) }
        let avg = Analytics.rollingAverage(points, days: 3)
        #expect(avg.count == 10)
        #expect(avg[0].kg == 0)
        #expect(avg[1].kg == 0.5)
        #expect(avg[5].kg == 4)          // mean of 3,4,5
        #expect(Set(avg.map(\.segment)) == [0])
    }

    @Test func rollingAverageBreaksAcrossLongGaps() {
        let points = [0, 1, 2, 40, 41].map { SeriesPoint(date: day($0), kg: 80) }
        let avg = Analytics.rollingAverage(points, days: 7)
        #expect(avg.map(\.segment) == [0, 0, 0, 1, 1])
    }

    @Test func recentAverageMatchesRollingAverage() {
        let points = [0, 3, 5, 6, 8, 12].map { SeriesPoint(date: day($0), kg: Double($0)) }
        let recent = Analytics.recentAverage(points, days: 7)!
        #expect(recent.count == 3)            // days 6, 8, 12 fall in the 7 days ending day 12
        #expect(recent.kg == Analytics.rollingAverage(points, days: 7).last!.kg)
        #expect(Analytics.recentAverage([], days: 7) == nil)
    }

    @Test func trendMovesTenPercentPerDay() {
        let points = [SeriesPoint(date: day(0), kg: 80), SeriesPoint(date: day(1), kg: 90)]
        let trend = Analytics.smoothedTrend(points, smoothing: 0.1)
        #expect(trend.count == 2)
        #expect(abs(trend[1].kg - 81) < 1e-9)
    }

    @Test func trendInterpolatesGaps() {
        // Two-day gap: interpolated day = 85, then 90. 80 → 80.5 → 81.45
        let points = [SeriesPoint(date: day(0), kg: 80), SeriesPoint(date: day(2), kg: 90)]
        let trend = Analytics.smoothedTrend(points, smoothing: 0.1)
        #expect(abs(trend[1].kg - 81.45) < 1e-9)
    }

    @Test func regressionRecoversSlope() {
        let points = (0..<30).map { SeriesPoint(date: day($0), kg: 100 - 0.1 * Double($0)) }
        let line = Analytics.linearRegression(points)!
        #expect(abs(line.slope + 0.1) < 1e-6)
        let goalDate = line.date(reaching: 95, after: day(0))!
        #expect(abs(goalDate.timeIntervalSince(day(50))) < 3700)  // within DST slop
    }

    @Test func statsForRange() {
        let points = (0..<14).map { SeriesPoint(date: day($0), kg: 80 + Double($0 % 3)) }
        let stats = Analytics.stats(readings: points, trend: points, in: day(0)...day(13))!
        #expect(stats.count == 14)
        #expect(stats.minimum.kg == 80)
        #expect(stats.maximum.kg == 82)
    }

    @Test func sliceIsInclusive() {
        let points = (0..<10).map { SeriesPoint(date: day($0), kg: 1) }
        #expect(Analytics.slice(points, in: day(2)...day(4)).count == 3)
        #expect(Analytics.slice(points, in: day(20)...day(30)).isEmpty)
    }

    @Test func projectionReachesGoal() {
        let trend = (0..<40).map { SeriesPoint(date: day($0), kg: 90 - 0.1 * Double($0)) }
        let projection = Projection.make(trend: trend, goalKg: 80, windowDays: 30)!
        #expect(projection.reachesGoal)
        #expect(projection.end.kg == 80)
    }

    @Test func niceAxisTicks() {
        let scale = YAxisScale.make(minKg: WeightUnit.pounds.kilograms(from: 181.2),
                                    maxKg: WeightUnit.pounds.kilograms(from: 188.9), unit: .pounds)
        let ticksLb = scale.ticks.map { (WeightUnit.pounds.value(fromKilograms: $0) * 10).rounded() / 10 }
        #expect(ticksLb.allSatisfy { $0.truncatingRemainder(dividingBy: 1) == 0 })
        #expect(ticksLb.first! <= 181 && ticksLb.last! >= 189)
    }

    @Test func formatting() {
        #expect(WeightUnit.pounds.formatDelta(-WeightUnit.pounds.kilograms(from: 2.14)) == "−2.1 lb")
        #expect(WeightUnit.kilograms.format(80) == "80.0 kg")
    }
}

@MainActor
struct ProjectionGuardTests {
    func trend(days: Int) -> [SeriesPoint] {
        (0..<days).map { SeriesPoint(date: Date(timeIntervalSince1970: 1_780_000_000 + Double($0) * 86_400), kg: 90 - 0.3 * Double($0)) }
    }

    @Test func noProjectionFromUnderTwoWeeks() {
        #expect(Projection.make(trend: trend(days: 8), goalKg: 80, windowDays: 30) == nil)
        #expect(Projection.weeklyRate(trend: trend(days: 8), windowDays: 30) == nil)
    }

    @Test func projectionAfterTwoWeeks() {
        #expect(Projection.make(trend: trend(days: 16), goalKg: 80, windowDays: 30) != nil)
    }
}

/// The weekly full re-check that catches deletions Health no longer reports.
@MainActor
struct FullResyncTests {
    @Test func dueWeeklyOrWhenNeverDone() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(WeightStore.isFullResyncDue(lastFullSync: nil, now: now))
        #expect(!WeightStore.isFullResyncDue(lastFullSync: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(WeightStore.isFullResyncDue(lastFullSync: now.addingTimeInterval(-8 * 86_400), now: now))
        #expect(WeightStore.isFullResyncDue(lastFullSync: now.addingTimeInterval(86_400), now: now))  // clock went backwards
    }

    @Test func missedDeletionIsRemoved() {
        let store = WeightStore(settings: AppSettings(), mode: .demo)
        let cached = store.entries
        let deletedElsewhere = cached[cached.count - 2]
        let addedElsewhere = WeightEntry(date: .now, kg: 80, sourceName: "Scale", sourceBundleID: "scale", isOwn: false)
        // What Health has now: one entry gone (its deletion record was purged), one new.
        let health = cached.filter { $0.id != deletedElsewhere.id } + [addedElsewhere]

        let removed = store.applyFullSnapshot(health, anchor: nil)

        #expect(removed == 1)
        #expect(!store.entries.contains { $0.id == deletedElsewhere.id })
        #expect(store.entries.contains { $0.id == addedElsewhere.id })
        #expect(store.entries.count == cached.count)
        #expect(store.lastFullSync != nil)
    }
}

struct LargeChangeWordingTests {
    @Test func saysHowMuchLessAndWhen() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = WeightEntry(date: now.addingTimeInterval(-2 * 86_400), kg: WeightUnit.pounds.kilograms(from: 198.1),
                                   sourceName: "t", sourceBundleID: "t", isOwn: true)
        let kg = WeightUnit.pounds.kilograms(from: 122.0)
        #expect(EntryCheck.isLargeChange(kg: kg, date: now, previous: previous))
        #expect(EntryCheck.largeChangeTitle(kg: kg, unit: .pounds) == "Save 122.0 lb?")
        #expect(EntryCheck.largeChangeMessage(kg: kg, previous: previous, unit: .pounds, now: now)
                == "That's 76.1 lb less than your 198.1 lb reading from 2 days ago.")
        let more = EntryCheck.largeChangeMessage(kg: previous.kg + 10, previous: previous, unit: .kilograms, now: now)
        #expect(more.hasPrefix("That's 10.0 kg more than"))
    }
}

struct DemoDataTests {
    @Test func nothingAfterTheEndTime() {
        let end = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: .now)!
        let entries = DemoData.entries(endingAt: end)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.date <= end })
    }
}
