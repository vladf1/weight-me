import SwiftUI

struct ChartScreen: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewport = ChartViewport(start: .now, length: nil)
    @State private var viewportInitialized = false
    @State private var selectedDate: Date?
    @State private var isEditingGoal = false

    private var series: DerivedSeries { store.series }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    if horizontalSizeClass == .regular {
                        regularLayout
                    } else {
                        compactLayout
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddEntryButton() }
            if store.isSyncing {
                ToolbarItem(placement: .topBarLeading) { ProgressView().controlSize(.small) }
            }
        }
        .sheet(isPresented: $isEditingGoal) { GoalEditorView() }
        .onAppear(perform: initializeViewportIfNeeded)
        .onChange(of: domain) { old, new in followLatestData(oldDomain: old, newDomain: new) }
    }

    // MARK: Layouts

    /// iOS 27 lets people share only the last 30 days of Health history. If everything we can see
    /// starts right around that cutoff, explain how to grant full history.
    private var looksHistoryLimited: Bool {
        guard store.mode == .health, !historyHintDismissed, let oldest = store.entries.first?.date else { return false }
        let age = Date.now.timeIntervalSince(oldest) / 86_400
        return age > 20 && age < 32
    }

    @AppStorage("historyHintDismissed") private var historyHintDismissed = false

    @ViewBuilder private var historyHint: some View {
        if looksHistoryLimited {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Only seeing the last 30 days?").font(.subheadline.weight(.semibold))
                    Text("Apple Health may be sharing limited history with WeightMe. To show everything: Settings › Health › Data Access & Devices › WeightMe › allow All Recorded Data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Dismiss", systemImage: "xmark") { historyHintDismissed = true }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            historyHint
            SummaryHeader(series: series, latest: store.latest, unit: settings.unit)
            rangePicker
            chart.containerRelativeFrame(.vertical) { height, _ in
                min(max(height * 0.48, 260), 520)
            }
            LayerChips()
            StatsPanel(stats: visibleStats, visibleRange: visibleRange, unit: settings.unit, columns: 2)
            GoalCard(series: series, projection: projection, unit: settings.unit) { isEditingGoal = true }
        }
        .padding()
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                historyHint
                SummaryHeader(series: series, latest: store.latest, unit: settings.unit)
                rangePicker
                chart.containerRelativeFrame(.vertical) { height, _ in
                    max(height - 290, 380)
                }
                LayerChips()
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                StatsPanel(stats: visibleStats, visibleRange: visibleRange, unit: settings.unit, columns: 2)
                GoalCard(series: series, projection: projection, unit: settings.unit) { isEditingGoal = true }
            }
            .frame(width: 340)
        }
        .padding(24)
    }

    private var chart: some View {
        WeightChartView(series: series, layers: settings.visibleLayers, unit: settings.unit,
                        goalKg: settings.goalKg, projection: projection, domain: domain,
                        viewport: $viewport, selectedDate: $selectedDate)
    }

    private var rangePicker: some View {
        HStack {
            Picker("Range", selection: Binding(get: { settings.chartRange }, set: { select($0) })) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            if isCustomZoom {
                Button("Reset", systemImage: "arrow.uturn.backward") { select(settings.chartRange) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isCustomZoom)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Weight Data Yet", systemImage: "scalemass")
        } description: {
            if store.status == .loading {
                Text("Reading your history from Apple Health…")
            } else {
                Text("Log your first weight, import a CSV from Settings, or check that WeightMe can read Weight in Settings › Health › Data Access & Devices.")
            }
        } actions: {
            Button("Log Weight") { router.isAddingEntry = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Viewport

    var domain: ClosedRange<Date> {
        guard let range = series.dateRange else {
            return Date.now.addingTimeInterval(-30 * 86_400)...Date.now
        }
        var upper = range.upperBound
        if settings.isVisible(.projection), let projection { upper = max(upper, projection.end.date) }
        return range.lowerBound.addingTimeInterval(-86_400)...upper.addingTimeInterval(86_400)
    }

    private var visibleRange: ClosedRange<Date> { viewport.range(in: domain) }

    private var visibleStats: RangeStats? {
        Analytics.stats(readings: series.readings, trend: series.trend, in: visibleRange)
    }

    private var isCustomZoom: Bool {
        let expected = settings.chartRange.days.map { TimeInterval($0) * 86_400 }
        switch (viewport.length, expected) {
        case (nil, nil): return false
        case let (a?, b?): return abs(a - b) > 3600
        default: return true
        }
    }

    private func initializeViewportIfNeeded() {
        guard !viewportInitialized, series.dateRange != nil else { return }
        viewportInitialized = true
        select(settings.chartRange, anchorToEnd: true)
    }

    private func select(_ range: ChartRange, anchorToEnd: Bool = false) {
        settings.chartRange = range
        guard let days = range.days else {
            viewport = ChartViewport(start: domain.lowerBound, length: nil)
            return
        }
        let length = TimeInterval(days) * 86_400
        let currentEnd = visibleRange.upperBound
        let atEnd = anchorToEnd || currentEnd >= latestDataDate
        let end = atEnd ? preferredEnd(forLength: length) : currentEnd
        viewport = ChartViewport(start: max(domain.lowerBound, end.addingTimeInterval(-length)), length: length)
    }

    private var latestDataDate: Date { series.readings.last?.date ?? domain.upperBound }

    /// Where the window should end when "showing the latest": just past the last reading, plus a little
    /// room for the projection line when it's on (never so much that short ranges show empty future).
    private func preferredEnd(forLength length: TimeInterval) -> Date {
        let breathingRoom = settings.isVisible(.projection) && projection != nil ? length * 0.12 : 0
        return min(domain.upperBound, latestDataDate.addingTimeInterval(max(86_400, breathingRoom)))
    }

    /// When new readings arrive and the chart was showing the latest data, keep showing the latest.
    private func followLatestData(oldDomain: ClosedRange<Date>, newDomain: ClosedRange<Date>) {
        if !viewportInitialized { initializeViewportIfNeeded(); return }
        guard let length = viewport.length else {
            viewport.start = newDomain.lowerBound
            return
        }
        let oldEnd = viewport.start.addingTimeInterval(length)
        if oldEnd.addingTimeInterval(3 * 86_400) >= latestDataDate {
            viewport.start = max(newDomain.lowerBound, preferredEnd(forLength: length).addingTimeInterval(-length))
        }
    }

    // MARK: Projection

    var projection: ProjectionLine? {
        Projection.make(trend: series.trend, goalKg: settings.goalKg, windowDays: settings.projectionWindowDays)
    }
}

enum Projection {
    /// Extends the recent trend (least-squares over the last `windowDays`) toward the goal.
    static func make(trend: [SeriesPoint], goalKg: Double?, windowDays: Int) -> ProjectionLine? {
        guard let last = trend.last else { return nil }
        let window = Analytics.slice(trend, in: last.date.addingTimeInterval(-Double(windowDays) * 86_400)...last.date)
        guard window.count >= 5, let line = Analytics.linearRegression(window) else { return nil }
        let start = SeriesPoint(date: last.date, kg: last.kg)
        if let goalKg {
            let needed = goalKg - last.kg
            if abs(needed) < 0.05 { return nil }
            if needed.sign == line.slope.sign, abs(line.slope) > 0.001 {
                let days = needed / line.slope
                if days <= 3 * 365 {
                    return ProjectionLine(start: start,
                                          end: SeriesPoint(date: last.date.addingTimeInterval(days * 86_400), kg: goalKg),
                                          reachesGoal: true)
                }
            }
        }
        let days = 60.0
        return ProjectionLine(start: start,
                              end: SeriesPoint(date: last.date.addingTimeInterval(days * 86_400), kg: last.kg + line.slope * days),
                              reachesGoal: false)
    }

    /// Rate in kg/week over the projection window.
    static func weeklyRate(trend: [SeriesPoint], windowDays: Int) -> Double? {
        guard let last = trend.last else { return nil }
        let window = Analytics.slice(trend, in: last.date.addingTimeInterval(-Double(windowDays) * 86_400)...last.date)
        guard window.count >= 5 else { return nil }
        return Analytics.linearRegression(window).map { $0.slope * 7 }
    }
}
