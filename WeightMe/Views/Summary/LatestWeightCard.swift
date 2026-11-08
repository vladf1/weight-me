import SwiftUI

/// The top of the front page: your latest weight, which is also where you log a new one.
///
/// At rest it shows the latest reading and the 7-day average. Drag the ruler or tap the number and it
/// switches to editing: the number turns accent-colored, the change from your last reading appears,
/// and Cancel / Save show up. Saving or cancelling returns it to rest.
struct LatestWeightCard: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var isEdited = false
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

    /// Your own reading from the last hour, which saving replaces (a quick fix for a typo or a
    /// re-weigh) instead of adding a second one. Readings from scales or other apps are never replaced,
    /// and backdated entries go through History's add sheet.
    private var replacing: WeightEntry? {
        guard let latest, latest.isOwn else { return nil }
        let age = Date.now.timeIntervalSince(latest.date)
        return (0..<Self.replaceWindow).contains(age) ? latest : nil
    }
    static let replaceWindow: TimeInterval = 3600

    /// What the new weight is compared with: the latest reading, or the one before it when replacing.
    private var previousEntry: WeightEntry? { store.entries.last { $0.date <= .now && $0.id != replacing?.id } }

    private var latestValue: Double? { latest.map { unit.value(fromKilograms: $0.kg) } }

    /// Where the ruler sits with nothing typed and no history.
    private var fallbackValue: Double { unit == .pounds ? 170 : 75 }

    private var displayRange: ClosedRange<Double> {
        unit.value(fromKilograms: WeightUnit.plausibleKilograms.lowerBound)...unit.value(fromKilograms: WeightUnit.plausibleKilograms.upperBound)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Both states are always laid out on top of each other, so the card is as tall as the
            // taller one and nothing below moves when you start or stop editing.
            ZStack(alignment: .top) {
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
                .frame(height: 44)

            ZStack {
                summary.visible(!isEditing)
                buttons.visible(isEditing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        .alert(parsedKg.map { EntryCheck.largeChangeTitle(kg: $0, unit: unit) } ?? "",
               isPresented: $confirmingLargeChange) {
            Button("Edit", role: .cancel) {}
            Button("Save", role: .confirm) { save() }
                .keyboardShortcut(.defaultAction)
        } message: {
            if let kg = parsedKg, let previous = previousEntry {
                Text(EntryCheck.largeChangeMessage(kg: kg, previous: previous, unit: unit))
            }
        }
    }

    // MARK: Pieces

    /// Editing: what saving will do (replace a recent reading, or the change from the last one).
    private var editingTopRow: some View {
        VStack(spacing: 3) {
            // Same font and spot as "Updated …" at rest, so only the words change.
            Text("New weight")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Group {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if parsedValue != nil, !isValid {
                    Text("Not a body weight in \(unit.name.lowercased())").foregroundStyle(.red)
                } else if !isSaving, let replacing {
                    Text("\(Image(systemName: "arrow.triangle.2.circlepath")) Replaces \(unit.format(replacing.kg)) from \(replacing.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("quickLogReplaces")
                } else if isEdited, !isSaving, let kg = parsedKg, let previous = previousEntry {
                    // Only for a value you entered, and not mid-save: Cancel restores the latest, and a
                    // save makes the new reading the "previous" one, while this row fades out.
                    HStack(spacing: 4) {
                        ChangeBadge(kg: kg - previous.kg, unit: unit)
                        Text("vs. \(previous.date.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(" ")   // keep this line's height so nothing shifts once you type
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)   // centered, like "Updated …" at rest
    }

    /// At rest, centered over the number: "Updated 2 hours ago" (and the source, if not WeightMe).
    private var restingTopRow: some View {
        HStack(spacing: 6) {
            // One line, so this row's height never changes (see `visible`).
            if showSaved {
                Text("\(Image(systemName: "checkmark.circle.fill")) Saved to Health")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Saved to Health")
            } else if let latest {
                let when = latest.date.formatted(.relative(presentation: .named))
                Text(latest.isOwn ? "Updated \(when)" : "Updated \(when) · \(latest.sourceName)")
                    .foregroundStyle(.secondary)
            }
            if store.isSyncing { ProgressView().controlSize(.mini) }
        }
        .font(.subheadline)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private var number: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(latestValue.map(Self.format) ?? "—", text: $text)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
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
        .padding(.horizontal, 16)
        // Fixed height: a focused text field is a little taller, which would nudge everything below.
        .frame(minWidth: 200, minHeight: 62, maxHeight: 62)
        // While typing, look like a text field: a lighter box with an accent outline.
        .background {
            let box = RoundedRectangle(cornerRadius: 14, style: .continuous)
            box.fill(Color(.systemBackground))
                .overlay(box.strokeBorder(Color.accentColor, lineWidth: 2))
                .opacity(fieldFocused ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: cancel) {
                Text("Cancel").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("quickLogCancel")
            Button(action: attemptSave) {
                Text(replacing == nil ? "Save" : "Replace").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isSaving)
            .accessibilityLabel("Save weight")
            .accessibilityIdentifier("quickLogSave")
        }
        .controlSize(.large)
    }

    /// At rest, in the space the editing buttons use: the 7-day average and its 30-day change.
    private var summary: some View {
        VStack(spacing: 4) {
            if let recent = Analytics.recentAverage(series.readings, days: 7) {
                Text("7-day average \(Text(unit.format(recent.kg)).fontWeight(.semibold).foregroundStyle(ChartPalette.color(for: .average7)))")
                    .monospacedDigit()
                if let change = change30 {
                    ChangeBadge(kg: change, unit: unit, suffix: "vs. 30 days ago")
                }
            } else {
                Text("Drag the ruler or tap the number to log your weight.")
                    .multilineTextAlignment(.center)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
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
            errorMessage = nil
            text = latestValue.map(Self.format) ?? ""
        }
    }

    private func attemptSave() {
        guard let kg = parsedKg, isValid else { return }
        if EntryCheck.isLargeChange(kg: kg, date: .now, previous: previousEntry) {
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
                if let replacing {
                    try await store.update(replacing, kg: kg, date: .now)
                } else {
                    try await store.add(kg: kg, date: .now)
                }
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
            Capsule().fill(Color.accentColor).frame(width: 3, height: 30)
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
