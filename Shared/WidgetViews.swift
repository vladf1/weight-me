import Charts
import SwiftUI
import WidgetKit

// Widget views live in Shared so the app can render them in a debug gallery.

// MARK: - Families

struct WidgetSmallView: View {
    let snapshot: WidgetSnapshot
    let latestKg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
            WidgetWeightValue(kg: latestKg, unit: snapshot.unit, size: 32)
            WidgetChangeLine(snapshot: snapshot)
            WidgetSparkline(snapshot: snapshot, showGoal: false)
                .frame(height: 26)
                .padding(.top, 4)
        }
        .widgetURL(DeepLink.addEntry)
    }
}

struct WidgetMediumView: View {
    let snapshot: WidgetSnapshot
    let latestKg: Double

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Weight", systemImage: "scalemass.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                WidgetWeightValue(kg: latestKg, unit: snapshot.unit, size: 34)
                if let date = snapshot.latestDate {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                WidgetChangeLine(snapshot: snapshot)
                Link(destination: DeepLink.addEntry) {
                    Label("Log", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.18), in: Capsule())
                }
                .padding(.top, 4)
            }
            .frame(width: 112, alignment: .leading)
            WidgetSparkline(snapshot: snapshot, showGoal: true, showReadings: true, showAxis: true)
        }
        .widgetURL(DeepLink.chart)
    }
}

struct WidgetRectangularView: View {
    let snapshot: WidgetSnapshot
    let latestKg: Double

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Weight").font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.unit.format(latestKg))
                    .font(.headline)
                    .widgetAccentable()
                if let change = snapshot.change30DaysKg {
                    Text("\(snapshot.unit.formatDelta(change)) 30d")
                        .font(.caption2)
                }
            }
            WidgetSparkline(snapshot: snapshot, showGoal: false)
        }
        .widgetURL(DeepLink.addEntry)
    }
}

struct WidgetCircularView: View {
    let snapshot: WidgetSnapshot
    let latestKg: Double

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(snapshot.unit.format(latestKg, decimals: 0, includeUnit: false))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(snapshot.unit.symbol)
                    .font(.caption2)
            }
        }
        .widgetURL(DeepLink.addEntry)
    }
}

struct WidgetInlineView: View {
    let snapshot: WidgetSnapshot
    let latestKg: Double

    var body: some View {
        if let change = snapshot.change30DaysKg {
            Text("\(Image(systemName: "scalemass")) \(snapshot.unit.format(latestKg)) · \(snapshot.unit.formatDelta(change, includeUnit: false))")
        } else {
            Text("\(Image(systemName: "scalemass")) \(snapshot.unit.format(latestKg))")
        }
    }
}

// MARK: - Pieces

struct WidgetWeightValue: View {
    let kg: Double
    let unit: WeightUnit
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(unit.format(kg, includeUnit: false))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetChangeLine: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let change = snapshot.change30DaysKg {
            let v = (snapshot.unit.value(fromKilograms: change) * 10).rounded() / 10
            HStack(spacing: 2) {
                Image(systemName: v < 0 ? "arrow.down.right" : v > 0 ? "arrow.up.right" : "arrow.right")
                Text("\(snapshot.unit.formatDelta(change)) · 30d")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(v < 0 ? Color.green : v > 0 ? Color.orange : Color.secondary)
        }
    }
}

struct WidgetSparkline: View {
    let snapshot: WidgetSnapshot
    var showGoal: Bool
    var showReadings = false
    var showAxis = false

    var body: some View {
        let values = snapshot.trend.map(\.kg) + (showReadings ? snapshot.readings.map(\.kg) : [])
        let goalInRange = showGoal ? snapshot.goalKg.flatMap { goal in
            (values.min().map { goal >= $0 - 3 } ?? false) ? goal : nil
        } : nil
        let lo = min(values.min() ?? 0, goalInRange ?? .infinity)
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.1, 0.3)
        Chart {
            if showReadings {
                ForEach(snapshot.readings) { p in
                    PointMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                        .symbolSize(6)
                        .foregroundStyle(Color.gray.opacity(0.5))
                }
            }
            ForEach(snapshot.trend) { p in
                LineMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                    .foregroundStyle(Color.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let goal = goalInRange {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.green.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(showAxis ? .automatic : .hidden)
        .chartYAxis(.hidden)
        .chartXAxis {
            if showAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
    }
}
