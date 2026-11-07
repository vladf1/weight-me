import Charts
import SwiftUI

/// Visible window of the chart: a leading date plus a length (nil = show everything).
struct ChartViewport: Equatable {
    var start: Date
    var length: TimeInterval?

    func range(in domain: ClosedRange<Date>) -> ClosedRange<Date> {
        guard let length else { return domain }
        let end = start.addingTimeInterval(length)
        return max(start, domain.lowerBound)...max(min(end, domain.upperBound), max(start, domain.lowerBound))
    }
}

struct ProjectionLine: Equatable {
    var start: SeriesPoint
    var end: SeriesPoint
    var reachesGoal: Bool
}

/// The main interactive weight chart: scroll, pinch to zoom, long-press (or drag in All) to inspect.
struct WeightChartView: View {
    let series: DerivedSeries
    let layers: Set<ChartLayer>
    let unit: WeightUnit
    let goalKg: Double?
    let projection: ProjectionLine?
    let domain: ClosedRange<Date>
    @Binding var viewport: ChartViewport
    @Binding var selectedDate: Date?

    @State private var zoomBaseLength: TimeInterval?

    private var fullSpan: TimeInterval { domain.upperBound.timeIntervalSince(domain.lowerBound) }
    private var visibleLength: TimeInterval { min(viewport.length ?? fullSpan, fullSpan) }
    private var isScrollable: Bool { viewport.length != nil && visibleLength < fullSpan - 3600 }
    private var visibleRange: ClosedRange<Date> { viewport.range(in: domain) }

    /// Data window handed to the chart: the visible range plus one screen on each side, so scrolling
    /// stays smooth while the number of marks stays small no matter how long the history is.
    private var dataWindow: ClosedRange<Date> {
        let range = visibleRange
        let pad = range.upperBound.timeIntervalSince(range.lowerBound)
        return range.lowerBound.addingTimeInterval(-pad)...range.upperBound.addingTimeInterval(pad)
    }

    private func windowed(_ points: [SeriesPoint], maxCount: Int) -> [SeriesPoint] {
        let slice = Analytics.slice(points, in: dataWindow)
        return Self.decimate(slice, maxCount: maxCount)
    }

    /// Evenly thins a series while always keeping segment boundaries and the last point.
    static func decimate(_ points: ArraySlice<SeriesPoint>, maxCount: Int) -> [SeriesPoint] {
        guard points.count > maxCount, maxCount > 1 else { return Array(points) }
        let step = Double(points.count) / Double(maxCount)
        var result: [SeriesPoint] = []
        result.reserveCapacity(maxCount + 8)
        var next = 0.0
        var previousSegment = points.first?.segment
        for (i, p) in zip(points.indices, points) {
            let offset = Double(i - points.startIndex)
            if offset >= next || p.segment != previousSegment || i == points.index(before: points.endIndex) {
                result.append(p)
                if offset >= next { next += step }
            }
            previousSegment = p.segment
        }
        return result
    }

    var body: some View {
        let visibleReadings = Analytics.slice(series.readings, in: visibleRange)
        let yScale = computeYScale()
        let selection = selectedDate.flatMap { Analytics.nearest(series.readings, to: $0) }
        let readings = windowed(series.readings, maxCount: 1500)
        let lineLayers: [(ChartLayer, [SeriesPoint])] = [ChartLayer.average90, .average30, .average7, .trend]
            .filter { layers.contains($0) }
            .map { ($0, windowed(series.points(for: $0), maxCount: 500)) }

        Chart {
            if layers.contains(.monthlyRange) {
                ForEach(series.monthly) { month in
                    BarMark(x: .value("Month", month.month, unit: .month),
                            yStart: .value("Low", month.minKg),
                            yEnd: .value("High", month.maxKg),
                            width: .ratio(0.7))
                        .foregroundStyle(ChartPalette.monthly.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            if layers.contains(.goal), let goalKg {
                RuleMark(y: .value("Goal", goalKg))
                    .foregroundStyle(ChartPalette.goal.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("Goal \(unit.format(goalKg))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ChartPalette.goal)
                    }
            }

            if layers.contains(.readings) {
                let showLine = visibleReadings.count <= 120
                let size = pointSize(visibleCount: visibleReadings.count)
                let opacity = visibleReadings.count > 300 ? 0.45 : 0.8
                ForEach(readings) { p in
                    if showLine {
                        LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg), series: .value("Series", "readings"))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    PointMark(x: .value("Date", p.date), y: .value("Weight", p.kg))
                        .symbolSize(size)
                        .foregroundStyle(Color.gray.opacity(opacity))
                }
            }

            ForEach(lineLayers, id: \.0) { layer, points in
                let isTrend = layer == .trend
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg),
                             series: .value("Series", "\(layer.rawValue)-\(p.segment)"))
                        .foregroundStyle(ChartPalette.color(for: layer))
                        .lineStyle(StrokeStyle(lineWidth: isTrend ? 3 : 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }

            if layers.contains(.projection), let projection {
                ForEach([projection.start, projection.end]) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Weight", point.kg),
                             series: .value("Series", "projection"))
                        .foregroundStyle(ChartPalette.projection.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                }
                PointMark(x: .value("Date", projection.end.date), y: .value("Weight", projection.end.kg))
                    .symbol(projection.reachesGoal ? .circle : .diamond)
                    .symbolSize(40)
                    .foregroundStyle(ChartPalette.projection)
            }

            if let selection {
                RuleMark(x: .value("Selected", selection.date))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(date: selection.date, readingKg: selection.kg, series: series,
                                         layers: layers, unit: unit)
                    }
                PointMark(x: .value("Selected", selection.date), y: .value("Weight", selection.kg))
                    .symbolSize(90)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        .chartYScale(domain: yScale.domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yScale.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(unit.format(kg, decimals: yScale.decimals, includeUnit: false))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: xAxisFormat, centered: false)
            }
        }
        .chartScrollableAxes(isScrollable ? .horizontal : [])
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(x: Binding(
            get: { viewport.start },
            set: { newValue in
                if viewport.start != newValue { viewport.start = newValue }
            }
        ))
        .chartXSelection(value: $selectedDate)
        .animation(.snappy(duration: 0.25), value: yScale)
        .simultaneousGesture(magnifyGesture)
        .accessibilityLabel("Weight chart")
    }

    // MARK: Pinch to zoom

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                let base = zoomBaseLength ?? visibleLength
                if zoomBaseLength == nil { zoomBaseLength = base }
                let center = viewport.start.addingTimeInterval(visibleLength / 2)
                let newLength = min(max(base / value.magnification, 3 * 86_400), fullSpan)
                var start = center.addingTimeInterval(-newLength / 2)
                start = min(max(start, domain.lowerBound), domain.upperBound.addingTimeInterval(-newLength))
                viewport = ChartViewport(start: start, length: newLength >= fullSpan ? nil : newLength)
            }
            .onEnded { _ in zoomBaseLength = nil }
    }

    // MARK: Helpers

    private func pointSize(visibleCount: Int) -> CGFloat {
        switch visibleCount {
        case ..<40: 36
        case ..<120: 22
        case ..<400: 12
        default: 6
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        let days = visibleLength / 86_400
        if days <= 10 { return .dateTime.weekday(.abbreviated).day() }
        if days <= 120 { return .dateTime.month(.abbreviated).day() }
        if days <= 800 { return .dateTime.month(.abbreviated).year(.twoDigits) }
        return .dateTime.year()
    }

    private func computeYScale() -> YAxisScale {
        let range = visibleRange
        var lo = Double.infinity, hi = -Double.infinity
        func include(_ points: ArraySlice<SeriesPoint>) {
            for p in points { lo = min(lo, p.kg); hi = max(hi, p.kg) }
        }
        let layerList: [ChartLayer] = [.readings, .average7, .average30, .average90, .trend]
        for layer in layerList where layers.contains(layer) {
            include(Analytics.slice(series.points(for: layer), in: range))
        }
        if layers.contains(.monthlyRange) {
            for m in series.monthly where range.contains(m.midMonth) { lo = min(lo, m.minKg); hi = max(hi, m.maxKg) }
        }
        if !lo.isFinite {
            // Nothing visible: fall back to everything.
            include(series.readings[...])
        }
        if !lo.isFinite { lo = 70; hi = 80 }
        if layers.contains(.projection), let projection, range.contains(projection.end.date) {
            lo = min(lo, projection.end.kg); hi = max(hi, projection.end.kg)
        }
        if layers.contains(.goal), let goalKg {
            let span = max(hi - lo, 1)
            if goalKg >= lo - span * 0.6 && goalKg <= hi + span * 0.6 {
                lo = min(lo, goalKg); hi = max(hi, goalKg)
            }
        }
        return YAxisScale.make(minKg: lo, maxKg: hi, unit: unit)
    }
}

/// Floating details shown while inspecting a point.
struct SelectionCallout: View {
    let date: Date
    let readingKg: Double
    let series: DerivedSeries
    let layers: Set<ChartLayer>
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(unit.format(readingKg))
                .font(.headline.monospacedDigit())
            ForEach([ChartLayer.average7, .average30, .average90, .trend], id: \.self) { layer in
                if layers.contains(layer), let p = Analytics.value(series.points(for: layer), at: date) {
                    HStack(spacing: 4) {
                        Circle().fill(ChartPalette.color(for: layer)).frame(width: 6, height: 6)
                        Text("\(layer.title) \(unit.format(p.kg))")
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}
