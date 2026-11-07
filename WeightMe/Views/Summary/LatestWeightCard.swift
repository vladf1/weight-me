import SwiftUI

/// The top of the front page: your latest weight, which is also where you log a new one.
///
/// At rest it shows the latest reading and the 7-day average. Drag the ruler or tap the number and it
/// switches to editing: the number turns accent-colored, the change from your last reading appears,
/// and Cancel / Save show up. Saving or cancelling returns it to rest.
struct LatestWeightCard: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var text = ""
    @State private var isEdited = false
    @State private var customDate: Date?
    @State private var isPickingDate = false
    @State private var isSaving = false
    @State private var savedCount = 0
    @State private var showSaved = false
    @State private var errorMessage: String?
    @State private var confirmingLargeChange = false
    @FocusState private var fieldFocused: Bool

    private var unit: WeightUnit { settings.unit }
    private var series: DerivedSeries { store.series }
    private var latest: WeightEntry? { store.latest }

    private var isEditing: Bool { isEdited || fieldFocused }

    private var parsedValue: Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var parsedKg: Double? { parsedValue.map { unit.kilograms(from: $0) } }

    private var isValid: Bool { parsedKg.map(WeightUnit.plausibleKilograms.contains) ?? false }

    private var date: Date { customDate ?? .now }

    private var previousEntry: WeightEntry? { store.entries.last { $0.date <= date } }

    private var latestValue: Double? { latest.map { unit.value(fromKilograms: $0.kg) } }

    /// Where the ruler sits with nothing typed and no history.
    private var fallbackValue: Double { unit == .pounds ? 170 : 75 }

    private var displayRange: ClosedRange<Double> {
        unit.value(fromKilograms: WeightUnit.plausibleKilograms.lowerBound)...unit.value(fromKilograms: WeightUnit.plausibleKilograms.upperBound)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Both states are always laid out on top of each other, so the card is as tall as the
            // taller one and nothing below moves when you start or stop editing.
            ZStack(alignment: .topLeading) {
                restingTopRow.visible(!isEditing)
                editingTopRow.visible(isEditing)
            }

            number

            WeightRuler(value: Binding(get: { parsedValue ?? latestValue ?? fallbackValue },
                                       set: { newValue in
                                           text = Self.format(newValue)
                                           withAnimation(.snappy) { isEdited = true }
                                           showSaved = false
                                           fieldFocused = false
                                       }),
                        range: displayRange)
                .frame(height: 54)

            ZStack {
                hint.visible(!isEditing)
                buttons.visible(isEditing)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .animation(.snappy, value: isEditing)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: syncFromLatest)
        .onChange(of: latest?.id) { syncFromLatest() }
        .onChange(of: unit) { cancel() }
        .onChange(of: fieldFocused) { _, focused in
            if focused, !isEdited {
                text = ""   // type straight over; the latest shows as the placeholder
            } else if !focused, text.isEmpty {
                cancel()
            }
        }
        .alert("Big change", isPresented: $confirmingLargeChange) {
            Button("Save Anyway") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let kg = parsedKg, let previous = previousEntry {
                Text("That's \(unit.formatDelta(kg - previous.kg)) from your previous reading of \(unit.format(previous.kg)). Is the unit right?")
            }
        }
    }

    // MARK: Pieces

    /// Editing: the change from your last reading (or what's wrong), and the date.
    private var editingTopRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("NEW WEIGHT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Group {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    } else if parsedValue != nil, !isValid {
                        Text("Not a body weight in \(unit.name.lowercased())").foregroundStyle(.red)
                    } else if let kg = parsedKg, let previous = previousEntry {
                        HStack(spacing: 4) {
                            ChangeBadge(kg: kg - previous.kg, unit: unit)
                            Text("vs. \(previous.date.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer()
            dateButton
        }
    }

    /// At rest: where the latest came from, and the 7-day average.
    private var restingTopRow: some View {
            AdaptiveStack(horizontalAlignment: .top, spacing: dynamicTypeSize.isAccessibilitySize ? 8 : nil) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("LATEST")
                        if store.isSyncing { ProgressView().controlSize(.mini) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    // One line each, so this row's height never changes (see `visible`).
                    if showSaved {
                        Text("\(Image(systemName: "checkmark.circle.fill")) Saved to Health")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .accessibilityLabel("Saved to Health")
                    } else if let latest {
                        Text("\(latest.date.formatted(.relative(presentation: .named))) · \(latest.sourceName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if let recent = Analytics.recentAverage(series.readings, days: 7) {
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                        Text("7-DAY AVERAGE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(unit.format(recent.kg))
                                .fontWeight(.semibold)
                                .foregroundStyle(ChartPalette.color(for: .average7))
                            Text("· \(recent.count == 1 ? "1 reading" : "\(recent.count) readings")")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.monospacedDigit())
                        .lineLimit(1)
                        .layoutPriority(1)
                        if let change = change30 {
                            ChangeBadge(kg: change, unit: unit, suffix: "vs. 30 days ago")
                        }
                    }
                }
            }
    }

    private var dateButton: some View {
        Button {
            isPickingDate = true
        } label: {
            HStack(spacing: 4) {
                Text(customDate.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? "Now")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isPickingDate ? 180 : 0))
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityLabel("Date and time")
        .accessibilityValue(customDate == nil ? "Now" : date.formatted())
        .popover(isPresented: $isPickingDate) {
            VStack(spacing: 12) {
                DatePicker("Date & Time", selection: Binding(get: { date }, set: { customDate = $0 }), in: ...Date.now)
                    .datePickerStyle(.graphical)
                HStack {
                    Button("Now") { customDate = nil; isPickingDate = false }
                    Spacer()
                    Button("Done") { isPickingDate = false }.fontWeight(.semibold)
                }
            }
            .padding()
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(latestValue.map(Self.format) ?? "—", text: $text)
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
                .fixedSize()
                .foregroundStyle(isEditing ? Color.accentColor : Color.primary)
                .contentTransition(.numericText())
                .accessibilityLabel(isEditing ? "New weight" : "Latest weight")
                .accessibilityIdentifier("quickLogField")
                .onChange(of: text) { _, new in
                    // Typing marks it edited; restoring the latest (Cancel) doesn't.
                    if fieldFocused, !new.isEmpty, new != latestValue.map(Self.format) {
                        isEdited = true
                        showSaved = false
                    }
                }
            Text(unit.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        // Fixed height: a focused text field is a little taller, which would nudge everything below.
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: cancel) {
                Text("Cancel").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("quickLogCancel")
            Button(action: attemptSave) {
                Text("Save").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isSaving)
            .accessibilityLabel("Save weight")
            .accessibilityIdentifier("quickLogSave")
        }
        .controlSize(.large)
    }

    private var hint: some View {
        Text(latest == nil ? "Drag the ruler or tap to enter your weight." : "Drag the ruler or tap the number to log a new weight.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: Actions

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }

    /// Change in the 7-day average compared with 30 days earlier.
    private var change30: Double? {
        guard let last = series.average7.last,
              let past = Analytics.value(series.average7, at: last.date.addingTimeInterval(-30 * 86_400), tolerance: 4 * 86_400)
        else { return nil }
        return last.kg - past.kg
    }

    private func syncFromLatest() {
        guard !isEditing else { return }
        text = latestValue.map(Self.format) ?? ""
    }

    private func cancel() {
        withAnimation(.snappy) {
            isEdited = false
            fieldFocused = false
            customDate = nil
            isPickingDate = false
            errorMessage = nil
            text = latestValue.map(Self.format) ?? ""
        }
    }

    private func attemptSave() {
        guard let kg = parsedKg, isValid else { return }
        if EntryCheck.isLargeChange(kg: kg, date: date, previous: previousEntry) {
            confirmingLargeChange = true
        } else {
            save()
        }
    }

    private func save() {
        guard let kg = parsedKg else { return }
        isSaving = true
        errorMessage = nil
        fieldFocused = false
        Task {
            do {
                try await store.add(kg: kg, date: date)
                // Back at rest; if this was backdated, the latest may be a different reading.
                cancel()
                withAnimation { showSaved = true }
                savedCount += 1
                let count = savedCount
                try? await Task.sleep(for: .seconds(3))
                if savedCount == count { withAnimation { showSaved = false } }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private extension View {
    /// Keeps the view in the layout (so it still takes up space) but hides it from sight, taps and
    /// VoiceOver when `isVisible` is false.
    func visible(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

/// A horizontal tape measure: drag left to go up, right to go down, in 0.1 steps with a tick of
/// haptic feedback per step.
struct WeightRuler: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step = 0.1

    /// Points per step.
    private let spacing: CGFloat = 9
    @State private var dragStartValue: Double?
    @State private var liveValue: Double?

    var body: some View {
        let shown = liveValue ?? value
        Canvas { context, size in
            let mid = size.width / 2
            let position = shown / step
            let centerIndex = position.rounded()
            let fraction = position - centerIndex
            let count = Int(mid / spacing) + 2
            for i in -count...count {
                let index = Int(centerIndex) + i
                let x = mid + (CGFloat(i) - fraction) * spacing
                let isWhole = index % 10 == 0
                let isHalf = index % 5 == 0
                let height: CGFloat = isWhole ? 26 : isHalf ? 18 : 11
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: height))
                context.stroke(tick, with: .color(.secondary.opacity(isWhole ? 0.9 : 0.5)), lineWidth: isWhole ? 1.5 : 1)
                if isWhole {
                    context.draw(Text("\(index / 10)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                                 at: CGPoint(x: x, y: size.height - 7))
                }
            }
        }
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                   .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .overlay(alignment: .top) {
            Capsule().fill(Color.accentColor).frame(width: 3, height: 34)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    let start = dragStartValue ?? value
                    dragStartValue = start
                    let raw = start - Double(drag.translation.width / spacing) * step
                    let clamped = min(max(raw, range.lowerBound), range.upperBound)
                    liveValue = clamped
                    let snapped = (clamped / step).rounded() * step
                    if abs(snapped - value) > step / 2 { value = snapped }
                }
                .onEnded { _ in
                    liveValue = nil
                    dragStartValue = nil
                }
        )
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Weight ruler")
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
