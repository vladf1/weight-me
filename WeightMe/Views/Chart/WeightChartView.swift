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

/// The main interactive weight chart: drag to pan, pinch to zoom, long-press (or drag in All) to inspect.
///
/// Panning is ours, not Swift Charts' scrollable axes: the chart only ever draws the visible window
/// (`chartXScale(domain: visibleRange)`). With native scrolling the chart's own offset and our
/// position binding could drift apart on fast flings, leaving a blank plot you couldn't drag out of.
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
    @State private var panStart: Date?
    @State private var momentum: Task<Void, Never>?

    private var fullSpan: TimeInterval { domain.upperBound.timeIntervalSince(domain.lowerBound) }
    private var visibleLength: TimeInterval { min(viewport.length ?? fullSpan, fullSpan) }
    private var isScrollable: Bool { viewport.length != nil && visibleLength < fullSpan - 3600 }
    private var visibleRange: ClosedRange<Date> { viewport.range(in: domain) }

    /// Data handed to the chart: the visible window plus one screen each side, so lines run off the
    /// edges toward their neighbors instead of stopping short. The plot clips the rest.
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
        let primary = isLongRange ? series.average7 : series.readings
        let visiblePrimary = Analytics.slice(primary, in: visibleRange)
        let yScale = computeYScale()
        let selection = selectedDate.flatMap { Analytics.nearest(primary, to: $0) }
        let readings = windowed(series.readings, maxCount: 1500)
        let lineLayers: [(ChartLayer, [SeriesPoint])] = [ChartLayer.average90, .average30, .average7, .trend]
            .filter { shown.contains($0) }
            .map { ($0, windowed(series.points(for: $0), maxCount: 1500)) }

        Chart {
            if showsMonthlyRange {
                ForEach(series.monthly) { month in
                    BarMark(x: .value("Month", month.month, unit: .month),
                            yStart: .value("Low", month.minKg),
                            yEnd: .value("High", month.maxKg),
                            width: .ratio(0.7))
                        .foregroundStyle(ChartPalette.monthly.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            if shown.contains(.goal), let goalKg {
                RuleMark(y: .value("Goal", goalKg))
                    .foregroundStyle(ChartPalette.goal.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            if shown.contains(.readings) {
                // A plain line through every entry, broken across long gaps (a lone reading gets a dot).
                // It steps back when a smoothed line is on top of it.
                let isMain = lineLayers.isEmpty
                let style = Color.gray.opacity(isMain ? 0.9 : 0.35)
                ForEach(Self.splitAtGaps(readings, maxGap: gapLimit)) { p in
                    if p.isLone {
                        PointMark(x: .value("Date", p.point.date), y: .value("Weight", p.point.kg))
                            .symbolSize(isMain ? 30 : 16)
                            .foregroundStyle(style)
                    } else {
                        LineMark(x: .value("Date", p.point.date), y: .value("Weight", p.point.kg),
                                 series: .value("Series", "readings-\(p.run)"))
                            .foregroundStyle(style)
                            .lineStyle(StrokeStyle(lineWidth: isMain ? 2.5 : 1.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            ForEach(lineLayers, id: \.0) { layer, points in
                let isTrend = layer == .trend
                // Standing in for Readings on a long range, the 7-day line breaks the way the readings line
                // does (only across long gaps) rather than at every week without data, which would leave
                // sparse stretches as one-point segments that draw nothing.
                let standsIn = layer == .average7 && isLongRange && layers.contains(.readings)
                if standsIn {
                    ForEach(Self.splitAtGaps(points, maxGap: gapLimit)) { p in
                        if p.isLone {
                            PointMark(x: .value("Date", p.point.date), y: .value("Weight", p.point.kg))
                                .symbolSize(30)
                                .foregroundStyle(ChartPalette.color(for: layer))
                        } else {
                            LineMark(x: .value("Date", p.point.date), y: .value("Weight", p.point.kg),
                                     series: .value("Series", "\(layer.rawValue)-\(p.run)"))
                                .foregroundStyle(ChartPalette.color(for: layer))
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                // Straight segments: a curve overshoots between far-apart points.
                                .interpolationMethod(.linear)
                        }
                    }
                } else {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Weight", p.kg),
                                 series: .value("Series", "\(layer.rawValue)-\(p.segment)"))
                            .foregroundStyle(ChartPalette.color(for: layer))
                            .lineStyle(StrokeStyle(lineWidth: isTrend ? 3 : 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }

            if shown.contains(.projection), let projection {
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
                PointMark(x: .value("Selected", selection.date), y: .value("Weight", selection.kg))
                    .symbolSize(90)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: visibleRange)
        .chartPlotStyle { $0.clipped() }
        .chartYScale(domain: yScale.domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yScale.ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(unit.format(kg, decimals: yScale.decimals, includeUnit: false))
                    }
                }
            }
        }
        .chartXAxis {
            // Labels and a short tick only: vertical grid lines made the chart busy.
            AxisMarks(values: xAxisTickDates) { value in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(centered: false) {
                    if let date = value.as(Date.self) { Text(xAxisLabel(for: date)) }
                }
            }
        }
        .chartOverlay(alignment: .topLeading) { proxy in
          ZStack(alignment: .topLeading) {
            // Catches drags anywhere on the plot, including stretches with nothing drawn.
            Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: proxy.plotSize.width, height: proxy.plotSize.height)
                .gesture(interaction(proxy: proxy))
            // Overlays rather than mark annotations, so labels can sit anywhere over the plot.
            ZStack(alignment: .topLeading) {
                if !series.readings.isEmpty, Analytics.slice(series.readings, in: visibleRange).isEmpty {
                    VStack(spacing: 2) {
                        Text("No weights in this period").font(.subheadline.weight(.semibold))
                        Text(isScrollable ? "Swipe to see more" : "").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: proxy.plotSize.width, height: proxy.plotSize.height)
                }
                if shown.contains(isLongRange ? .average7 : .readings), selection == nil {
                    EndpointLabels(proxy: proxy, visible: visiblePrimary, leftEdge: visibleRange.lowerBound, unit: unit)
                }
                if shown.contains(.goal), let goalKg, let y = proxy.position(forY: goalKg),
                   y >= 14, y <= proxy.plotSize.height {
                    Text("Goal \(unit.format(goalKg))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ChartPalette.goal)
                        .padding(.horizontal, 4)
                        .background(.background.opacity(0.8), in: Capsule())
                        .offset(x: 4, y: y - 16)
                }
                if let selection, let x = proxy.position(forX: selection.date) {
                    // Put the callout in the top corner away from the finger.
                    let onRight = x < proxy.plotSize.width / 2
                    HStack {
                        if onRight { Spacer(minLength: 0) }
                        SelectionCallout(date: selection.date, readingKg: selection.kg, series: series,
                                         layers: isLongRange ? shown.subtracting([.average7]) : shown, unit: unit,
                                         valueLabel: isLongRange ? ChartLayer.average7.title : nil)
                        if !onRight { Spacer(minLength: 0) }
                    }
                    .frame(width: proxy.plotSize.width)
                    .padding(6)
                    .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
          }
        }
        // No implicit animation on y-scale changes: animating the marks while a fast fling swaps the
        // data under them could leave the chart stuck mid-transition with no line and no dates.
        .simultaneousGesture(magnifyGesture)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel("Weight chart")
        .accessibilityIdentifier("weightChart")
    }

    // MARK: Pan and inspect

    /// Long-press then drag inspects; a plain drag pans (in All, where there's nothing to pan,
    /// a drag inspects straight away).
    private func interaction(proxy: ChartProxy) -> some Gesture {
        let plotWidth = max(proxy.plotSize.width, 1)
        func select(at x: CGFloat) {
            if let date: Date = proxy.value(atX: x) { selectedDate = date }
        }
        let inspect = LongPressGesture(minimumDuration: isScrollable ? 0.3 : 0)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value { select(at: drag.location.x) }
            }
            .onEnded { _ in selectedDate = nil }
        let pan = DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isScrollable else { return }
                momentum?.cancel()
                let start = panStart ?? viewport.start
                if panStart == nil { panStart = start }
                let secondsPerPoint = visibleLength / plotWidth
                setStart(start.addingTimeInterval(-value.translation.width * secondsPerPoint))
            }
            .onEnded { value in
                panStart = nil
                guard isScrollable else { return }
                // A little momentum: glide in the direction of the flick, slowing to a stop.
                let secondsPerPoint = visibleLength / plotWidth
                var velocity = -(value.predictedEndTranslation.width - value.translation.width) * secondsPerPoint * 4
                momentum = Task { @MainActor in
                    while abs(velocity) * 0.016 > visibleLength / 2000, !Task.isCancelled {
                        setStart(viewport.start.addingTimeInterval(velocity * 0.016))
                        velocity *= 0.92
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
            }
        return inspect.exclusively(before: pan)
    }

    private func setStart(_ start: Date) {
        let latest = domain.upperBound.addingTimeInterval(-visibleLength)
        viewport.start = min(max(start, domain.lowerBound), max(latest, domain.lowerBound))
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

    private var visibleDays: Double { visibleLength / 86_400 }

    /// Readings further apart than the visible span aren't joined by a line. Gaps you can see across
    /// stay connected, but a window with no readings in it (whose neighbors are necessarily more than a
    /// window apart) shows as empty instead of as a diagonal between distant readings.
    private var gapLimit: TimeInterval { visibleLength }

    struct RunPoint: Identifiable {
        var point: SeriesPoint
        /// Which unbroken run of the line this point belongs to.
        var run: Int
        /// No neighbor within the gap limit on either side: drawn as a dot.
        var isLone: Bool
        var id: Date { point.date }
    }

    /// Splits a line wherever consecutive points are more than `maxGap` apart.
    static func splitAtGaps(_ points: [SeriesPoint], maxGap: TimeInterval) -> [RunPoint] {
        var result: [RunPoint] = []
        result.reserveCapacity(points.count)
        var run = 0
        for (i, p) in points.enumerated() {
            let joinsPrevious = i > 0 && p.date.timeIntervalSince(points[i - 1].date) <= maxGap
            let joinsNext = i + 1 < points.count && points[i + 1].date.timeIntervalSince(p.date) <= maxGap
            if i > 0, !joinsPrevious { run += 1 }
            result.append(RunPoint(point: p, run: run, isLone: !joinsPrevious && !joinsNext))
        }
        return result
    }

    /// Long ranges plot the 7-day average instead of every reading (see `longRangeDays`).
    private var isLongRange: Bool { visibleDays >= longRangeDays }
    private var shown: Set<ChartLayer> { layers.shown(longRange: isLongRange) }

    /// Month-wide bars only make sense when several months are on screen.
    private var showsMonthlyRange: Bool { shown.contains(.monthlyRange) && visibleDays >= 90 }

    /// Calendar-aligned ticks (days, weeks, months, quarters, half-years or years depending on zoom),
    /// generated only for the data window around the screen. Striding over the whole history makes
    /// Swift Charts lay out thousands of axis marks and hang.
    private var xAxisTickDates: [Date] {
        let calendar = Calendar.current
        let (component, count): (Calendar.Component, Int) = switch visibleDays {
        case ...10: (.day, 1)
        case ...45: (.weekOfYear, 1)
        case ...200: (.month, 1)
        case ...400: (.month, 3)
        case ...800: (.month, 6)
        case ...3000: (.year, 1)
        default: (.year, 2)
        }
        let window = visibleRange
        guard var tick = calendar.dateInterval(of: component == .weekOfYear ? .weekOfYear : (component == .day ? .day : (component == .month ? .month : .year)),
                                               for: window.lowerBound)?.start else { return [] }
        // Align multi-month / multi-year strides to calendar boundaries (Jan/Apr/Jul/Oct, even years…).
        if count > 1 {
            while true {
                let unitValue = component == .month ? calendar.component(.month, from: tick) - 1 : calendar.component(.year, from: tick)
                if unitValue % count == 0 { break }
                tick = calendar.date(byAdding: component, value: 1, to: tick)!
            }
        }
        var ticks: [Date] = []
        while tick <= window.upperBound, ticks.count < 120 {
            // A tick before the first reading would put its label left of the plot, outside the card.
            if tick >= max(domain.lowerBound, window.lowerBound) { ticks.append(tick) }
            tick = calendar.date(byAdding: component, value: count, to: tick)!
        }
        return ticks
    }

    /// "Mon 3", "Mar 3", "Mar", "Jan ’26", "2026" — the year is only spelled out on January ticks.
    private func xAxisLabel(for date: Date) -> String {
        switch visibleDays {
        case ...10:
            return date.formatted(.dateTime.weekday(.abbreviated).day())
        case ...45:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case ...800:
            let month = date.formatted(.dateTime.month(.abbreviated))
            if Calendar.current.component(.month, from: date) == 1 {
                return "\(month) ’\(date.formatted(.dateTime.year(.twoDigits)))"
            }
            return month
        default:
            return date.formatted(.dateTime.year())
        }
    }

    private func computeYScale() -> YAxisScale {
        let range = visibleRange
        var lo = Double.infinity, hi = -Double.infinity
        func include(_ points: ArraySlice<SeriesPoint>) {
            for p in points { lo = min(lo, p.kg); hi = max(hi, p.kg) }
        }
        let layerList: [ChartLayer] = [.readings, .average7, .average30, .average90, .trend]
        for layer in layerList where shown.contains(layer) {
            let points = series.points(for: layer)
            include(Analytics.slice(points, in: range))
            // Where a line crosses the left and right edges on its way to a reading off-screen. Keeping
            // those in range keeps the visible part of the line inside the plot, with no clipping (clipping
            // the plot of a scrollable chart hides its date labels).
            let breaksAtGaps = layer == .readings || (layer == .average7 && isLongRange && layers.contains(.readings))
            for edge in [range.lowerBound, range.upperBound] {
                if let kg = Self.lineValue(points, at: edge, maxGap: breaksAtGaps ? gapLimit : nil) { lo = min(lo, kg); hi = max(hi, kg) }
            }
        }
        if showsMonthlyRange {
            for m in series.monthly where range.contains(m.midMonth) { lo = min(lo, m.minKg); hi = max(hi, m.maxKg) }
        }
        if !lo.isFinite {
            // Nothing visible: fall back to everything.
            include(series.readings[...])
        }
        if !lo.isFinite { lo = 70; hi = 80 }
        if shown.contains(.projection), let projection, range.contains(projection.end.date) {
            lo = min(lo, projection.end.kg); hi = max(hi, projection.end.kg)
        }
        if shown.contains(.goal), let goalKg {
            let span = max(hi - lo, 1)
            if goalKg >= lo - span * 0.6 && goalKg <= hi + span * 0.6 {
                lo = min(lo, goalKg); hi = max(hi, goalKg)
            }
        }
        return YAxisScale.make(minKg: lo, maxKg: hi, unit: unit)
    }

    /// The straight-line value of a series at `date`, between the points on either side of it.
    /// Nil at the ends of the data, or across a gap the line doesn't draw (longer than `maxGap`, or
    /// between segments when there's no `maxGap`).
    static func lineValue(_ points: [SeriesPoint], at date: Date, maxGap: TimeInterval?) -> Double? {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0, lo < points.count else { return nil }
        let a = points[lo - 1], b = points[lo]
        if let maxGap {
            guard b.date.timeIntervalSince(a.date) <= maxGap else { return nil }
        } else {
            guard a.segment == b.segment else { return nil }
        }
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return b.kg }
        return a.kg + (b.kg - a.kg) * date.timeIntervalSince(a.date) / span
    }
}

/// Value tags on the first and last entry on screen: the first sits just right of its point,
/// the last sits above its point.
private struct EndpointLabels: View {
    let proxy: ChartProxy
    let visible: ArraySlice<SeriesPoint>
    let leftEdge: Date
    let unit: WeightUnit

    var body: some View {
        // Positions are measured from the left edge of what's on screen, so this works whether
        // the proxy reports scrolled-content or on-screen coordinates.
        let plot = proxy.plotSize
        if let first = visible.first, let last = visible.last,
           let x0 = proxy.position(forX: leftEdge),
           let firstX = proxy.position(forX: first.date).map({ $0 - x0 }),
           let firstY = proxy.position(forY: first.kg),
           let lastX = proxy.position(forX: last.date).map({ $0 - x0 }),
           let lastY = proxy.position(forY: last.kg) {
            // Each tag sits in a zero-height, plot-wide strip placed at its point's height.
            ZStack {
                if visible.count > 1 {
                    // Arrow tip on the first entry in view (not the plot edge, which the line
                    // may cross at a different height on its way in from an earlier entry).
                    tag(first.kg, pointer: .left)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            -min(max(firstX + 2, 0), plot.width - d.width)
                        }
                        .frame(width: plot.width, height: 0, alignment: .leading)
                        .position(x: plot.width / 2, y: firstY)
                }
                // The bubble slides to stay inside the plot; the arrow and dot stay on the point.
                tag(last.kg, pointer: nil)
                    .fixedSize()
                    .alignmentGuide(HorizontalAlignment.center) { d in
                        let left = min(max(lastX - d.width / 2, 0), plot.width - d.width)
                        return plot.width / 2 - left
                    }
                    .frame(width: plot.width, height: 0, alignment: .bottom)
                    .position(x: plot.width / 2, y: lastY - 12)
                Triangle()
                    .rotation(.degrees(180))
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 6)
                    .position(x: min(max(lastX, 8), plot.width - 8), y: lastY - 10)
                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .position(x: lastX, y: lastY)
            }
            .frame(width: plot.width, height: plot.height)
        }
    }

    private enum Pointer { case left }

    private func tag(_ kg: Double, pointer: Pointer?) -> some View {
        let text = Text(unit.format(kg, includeUnit: false))
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
        return Group {
            switch pointer {
            case .left:
                HStack(spacing: -1) {
                    Triangle().rotation(.degrees(-90)).fill(Color.accentColor).frame(width: 8, height: 6)
                    text
                }
            case nil:
                text
            }
        }
    }
}

nonisolated private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// Floating details shown while inspecting a point.
struct SelectionCallout: View {
    let date: Date
    let readingKg: Double
    let series: DerivedSeries
    let layers: Set<ChartLayer>
    let unit: WeightUnit
    /// Names the main value when it isn't a single reading (e.g. "7-day avg" on long ranges).
    var valueLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let valueLabel {
                Text(valueLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
