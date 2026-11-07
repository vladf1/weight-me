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

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            SummaryHeader(series: series, latest: store.latest, unit: settings.unit)
            rangePicker
            chart.frame(height: 340)
            LayerChips()
            StatsPanel(stats: visibleStats, visibleRange: visibleRange, unit: settings.unit, columns: 2)
            GoalCard(series: series, projection: projection, unit: settings.unit) { isEditingGoal = true }
        }
        .padding()
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                SummaryHeader(series: series, latest: store.latest, unit: settings.unit)
                rangePicker
                chart.frame(minHeight: 420, idealHeight: 520)
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
        let currentEnd = visibleRange.upperBound
        let atEnd = anchorToEnd || domain.upperBound.timeIntervalSince(currentEnd) < 2 * 86_400
        let end = atEnd ? domain.upperBound : currentEnd
        guard let days = range.days else {
            viewport = ChartViewport(start: domain.lowerBound, length: nil)
            return
        }
        let length = TimeInterval(days) * 86_400
        viewport = ChartViewport(start: max(domain.lowerBound, end.addingTimeInterval(-length)), length: length)
    }

    /// When new readings arrive and the chart was showing the latest data, keep showing the latest.
    private func followLatestData(oldDomain: ClosedRange<Date>, newDomain: ClosedRange<Date>) {
        if !viewportInitialized { initializeViewportIfNeeded(); return }
        guard let length = viewport.length else {
            viewport.start = newDomain.lowerBound
            return
        }
        let oldEnd = viewport.start.addingTimeInterval(length)
        if oldDomain.upperBound.timeIntervalSince(oldEnd) < 2 * 86_400 {
            viewport.start = max(newDomain.lowerBound, newDomain.upperBound.addingTimeInterval(-length))
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
