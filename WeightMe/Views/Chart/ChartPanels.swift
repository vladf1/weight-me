import SwiftUI

/// "↓ 2.1 lb · 30 days" — green when going down (weight-loss oriented app).
struct ChangeBadge: View {
    let kg: Double
    let unit: WeightUnit
    var suffix: String? = nil
    var font: Font = .caption

    var body: some View {
        let value = unit.value(fromKilograms: kg)
        let rounded = (value * 10).rounded() / 10
        let symbol = rounded < 0 ? "arrow.down.right" : rounded > 0 ? "arrow.up.right" : "arrow.right"
        let color: Color = rounded < 0 ? .green : rounded > 0 ? .orange : .secondary
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(unit.formatDelta(kg))
            if let suffix { Text("· \(suffix)").foregroundStyle(.secondary) }
        }
        .font(font.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .foregroundStyle(color)
    }
}

/// Toggle chips that double as the chart legend.
struct LayerChips: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ChartLayer.allCases) { layer in
                    let isOn = settings.isVisible(layer)
                    Button {
                        withAnimation(.snappy) { settings.toggle(layer) }
                    } label: {
                        HStack(spacing: 6) {
                            swatch(for: layer)
                            Text(layer.title)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isOn ? ChartPalette.color(for: layer).opacity(0.16) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? ChartPalette.color(for: layer).opacity(0.5) : .clear))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func swatch(for layer: ChartLayer) -> some View {
        let color = ChartPalette.color(for: layer)
        switch layer {
        case .readings:
            Circle().fill(color).frame(width: 8, height: 8)
        case .goal, .projection:
            Capsule().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 14, height: 2)
        case .monthlyRange:
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.4)).frame(width: 8, height: 12)
        default:
            Capsule().fill(color).frame(width: 14, height: 3)
        }
    }
}

/// Statistics for whatever is currently visible on the chart.
struct StatsPanel: View {
    let stats: RangeStats?
    let visibleRange: ClosedRange<Date>
    let unit: WeightUnit
    var columns: Int = 2
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : self.columns
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack {
                Text("In View").font(.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let stats {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    StatTile(title: "Change", value: unit.formatDelta(stats.change),
                             detail: "trend", tint: stats.change < 0 ? .green : (stats.change > 0 ? .orange : .secondary))
                    StatTile(title: "Weekly rate",
                             value: stats.weeklyRate.map { "\(unit.formatDelta($0, includeUnit: false)) \(unit.symbol)/wk" } ?? "—",
                             detail: "linear fit", tint: .primary)
                    StatTile(title: "Lowest", value: unit.format(stats.minimum.kg),
                             detail: stats.minimum.date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)), tint: .primary)
                    StatTile(title: "Highest", value: unit.format(stats.maximum.kg),
                             detail: stats.maximum.date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)), tint: .primary)
                    StatTile(title: "Average", value: unit.format(stats.mean), detail: nil, tint: .primary)
                    StatTile(title: "Readings", value: stats.count.formatted(), detail: nil, tint: .primary)
                }
            } else {
                Text("No readings in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var rangeText: String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year(.twoDigits)
        return "\(visibleRange.lowerBound.formatted(style)) – \(visibleRange.upperBound.formatted(style))"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Goal progress and the projected date of reaching it.
struct GoalCard: View {
    @Environment(AppSettings.self) private var settings
    let series: DerivedSeries
    let projection: ProjectionLine?
    let unit: WeightUnit
    let editGoal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Goal", systemImage: "flag.checkered")
                    .font(.headline)
                Spacer()
                Button(settings.goalKg == nil ? "Set Goal" : "Edit", action: editGoal)
                    .font(.subheadline)
            }
            if let goal = settings.goalKg, let current = series.trend.last?.kg {
                let remaining = current - goal
                AdaptiveStack(horizontalAlignment: .firstTextBaseline) {
                    Text(unit.format(goal))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ChartPalette.goal)
                    Spacer()
                    if abs(unit.value(fromKilograms: remaining)) < 0.05 {
                        Text("Reached! 🎉").font(.subheadline.weight(.semibold))
                    } else {
                        Text("\(unit.format(abs(remaining))) to go")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(projectionText(goal: goal, current: current))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Set a goal weight to see it on the chart and get a projected date based on your recent trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func projectionText(goal: Double, current: Double) -> String {
        let window = settings.projectionWindowDays
        guard let rate = Projection.weeklyRate(trend: series.trend, windowDays: window) else {
            return "Not enough recent data to project a date."
        }
        let rateText = "\(unit.formatDelta(rate)) per week"
        if let projection, projection.reachesGoal {
            let date = projection.end.date.formatted(.dateTime.month(.wide).day().year())
            return "At your \(window)-day rate of \(rateText), you'd reach it around \(date)."
        }
        let headingAway = (goal < current && rate > 0) || (goal > current && rate < 0)
        if headingAway {
            return "Your \(window)-day trend (\(rateText)) is heading away from your goal."
        }
        return "At \(rateText), the goal is more than 3 years out."
    }
}
