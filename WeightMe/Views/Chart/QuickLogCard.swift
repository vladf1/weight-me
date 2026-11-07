import SwiftUI

/// Front-page logging: the number starts at your latest weight, drag the ruler (or tap the number
/// to type) and hit Save. Logs "now" unless you pick another time.
struct QuickLogCard: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var isEdited = false
    @State private var customDate: Date?
    @State private var isPickingDate = false
    @State private var isSaving = false
    @State private var justSaved = false
    @State private var savedCount = 0
    @State private var errorMessage: String?
    @State private var confirmingLargeChange = false
    @FocusState private var fieldFocused: Bool

    private var unit: WeightUnit { settings.unit }

    private var parsedValue: Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var parsedKg: Double? { parsedValue.map { unit.kilograms(from: $0) } }

    private var isValid: Bool { parsedKg.map(WeightUnit.plausibleKilograms.contains) ?? false }

    private var date: Date { customDate ?? .now }

    private var previousEntry: WeightEntry? { store.entries.last { $0.date <= date } }

    /// Where the ruler sits when there's nothing typed yet and no history.
    private var fallbackValue: Double { unit == .pounds ? 170 : 75 }

    private var displayRange: ClosedRange<Double> {
        unit.value(fromKilograms: WeightUnit.plausibleKilograms.lowerBound)...unit.value(fromKilograms: WeightUnit.plausibleKilograms.upperBound)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Log Weight").font(.headline)
                Spacer()
                Button {
                    withAnimation(.snappy) { isPickingDate.toggle() }
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
            }

            if isPickingDate {
                HStack {
                    DatePicker("Date & Time", selection: Binding(get: { date }, set: { customDate = $0 }), in: ...Date.now)
                        .labelsHidden()
                    Spacer()
                    if customDate != nil {
                        Button("Now") { withAnimation(.snappy) { customDate = nil; isPickingDate = false } }
                            .font(.subheadline)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("—", text: $text)
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .fixedSize()
                    .foregroundStyle(isEdited ? Color.accentColor : Color.primary)
                    .accessibilityLabel("New weight")
                    .accessibilityIdentifier("quickLogField")
                    .onChange(of: text) { if fieldFocused { isEdited = true; justSaved = false } }
                Text(unit.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }

            WeightRuler(value: Binding(get: { parsedValue ?? fallbackValue },
                                       set: { newValue in
                                           text = Self.format(newValue)
                                           isEdited = true
                                           justSaved = false
                                           fieldFocused = false
                                       }),
                        range: displayRange)
                .frame(height: 54)

            hint
                .font(.caption)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 16)

            Button(action: attemptSave) {
                Group {
                    if justSaved {
                        Label("Saved to Apple Health", systemImage: "checkmark")
                    } else {
                        Text("Save")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(justSaved ? .green : .accentColor)
            .controlSize(.large)
            .disabled(!isValid || isSaving)
            .accessibilityLabel(justSaved ? "Saved to Apple Health" : "Save weight")
            .accessibilityIdentifier("quickLogSave")
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: syncFromLatest)
        .onChange(of: store.latest?.id) { syncFromLatest() }
        .onChange(of: unit) { isEdited = false; syncFromLatest() }
        .alert("Big change", isPresented: $confirmingLargeChange) {
            Button("Save Anyway") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let kg = parsedKg, let previous = previousEntry {
                Text("That's \(unit.formatDelta(kg - previous.kg)) from your previous reading of \(unit.format(previous.kg)). Is the unit right?")
            }
        }
    }

    @ViewBuilder private var hint: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if parsedValue != nil, !isValid {
            Text("That doesn't look like a body weight in \(unit.name.lowercased()).").foregroundStyle(.red)
        } else if justSaved {
            Text(" ")
        } else if isEdited, let kg = parsedKg, let previous = previousEntry {
            HStack(spacing: 4) {
                ChangeBadge(kg: kg - previous.kg, unit: unit)
                Text("vs. \(unit.format(previous.kg)) \(previous.date.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
            }
        } else if store.latest != nil {
            Text("Starts at your latest. Drag the ruler or tap the number.").foregroundStyle(.secondary)
        } else {
            Text("Drag the ruler or tap to type your weight.").foregroundStyle(.secondary)
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }

    private func syncFromLatest() {
        guard !isEdited, !fieldFocused else { return }
        if let latest = store.latest {
            text = Self.format(unit.value(fromKilograms: latest.kg))
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
                isEdited = false
                customDate = nil
                withAnimation(.snappy) { isPickingDate = false; justSaved = true }
                savedCount += 1
                let count = savedCount
                try? await Task.sleep(for: .seconds(2.5))
                if savedCount == count { withAnimation { justSaved = false } }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
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
                    withAnimation(.snappy(duration: 0.2)) { liveValue = nil }
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
