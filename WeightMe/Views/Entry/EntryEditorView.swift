import SwiftUI

/// Sheet for logging a new weight or editing one this app wrote.
struct EntryEditorView: View {
    enum Mode {
        case add
        case edit(WeightEntry)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var text = ""
    @State private var unit: WeightUnit = .pounds
    @State private var date = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmingLargeChange = false
    @State private var confirmingDelete = false
    @State private var didLoad = false
    @FocusState private var fieldFocused: Bool

    private var editingEntry: WeightEntry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }

    private var parsedValue: Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var parsedKg: Double? { parsedValue.map { unit.kilograms(from: $0) } }

    private var isValid: Bool {
        guard let kg = parsedKg else { return false }
        return WeightUnit.plausibleKilograms.contains(kg)
    }

    /// The reading just before this one (ignoring the entry being edited) — for the sanity check.
    private var previousEntry: WeightEntry? {
        store.entries.last { $0.date <= date && $0.id != editingEntry?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        HStack(spacing: 18) {
                            stepButton("minus", delta: -0.1)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                TextField("0.0", text: $text)
                                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                    .multilineTextAlignment(.center)
                                    .keyboardType(.decimalPad)
                                    .focused($fieldFocused)
                                    .fixedSize()
                                    .accessibilityLabel("Weight")
                                Text(unit.symbol)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            .frame(maxWidth: .infinity)
                            stepButton("plus", delta: 0.1)
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Picker("Unit", selection: $unit) {
                            ForEach(WeightUnit.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        if let previous = previousEntry, let kg = parsedKg, isValid {
                            AdaptiveStack(spacing: 4) {
                                Text("vs. \(unit.format(previous.kg)) on \(previous.date.formatted(.dateTime.month(.abbreviated).day()))")
                                    .foregroundStyle(.secondary)
                                ChangeBadge(kg: kg - previous.kg, unit: unit)
                            }
                            .font(.caption)
                        } else if parsedValue != nil, !isValid {
                            Text("That doesn't look like a body weight in \(unit.name.lowercased()).")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    DatePicker("Date & Time", selection: $date, in: ...Date.now)
                } footer: {
                    if editingEntry != nil {
                        Text("Apple Health entries can't be changed in place, so saving replaces the original entry with a new one.")
                    } else {
                        Text("Saved to Apple Health.")
                    }
                }

                if editingEntry != nil {
                    Section {
                        Button("Delete Entry", role: .destructive) { confirmingDelete = true }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingEntry == nil ? "Log Weight" : "Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(!isValid || isSaving)
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
            .confirmationDialog("Delete this entry from Apple Health?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text("This can't be undone.")
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let current = parsedValue ?? 0
            text = max(0, current + delta).formatted(.number.precision(.fractionLength(1)).grouping(.never))
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(delta > 0 ? "Increase" : "Decrease")
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        unit = settings.unit
        if let entry = editingEntry {
            date = entry.date
            text = unit.value(fromKilograms: entry.kg).formatted(.number.precision(.fractionLength(1)).grouping(.never))
        } else {
            if let last = store.latest {
                text = unit.value(fromKilograms: last.kg).formatted(.number.precision(.fractionLength(1)).grouping(.never))
            }
            fieldFocused = true
        }
    }

    private func attemptSave() {
        guard let kg = parsedKg, isValid else { return }
        if let previous = previousEntry {
            let change = abs(kg - previous.kg)
            let days = abs(date.timeIntervalSince(previous.date)) / 86_400
            if change > max(2.5, previous.kg * 0.03) && days < 10 {
                confirmingLargeChange = true
                return
            }
        }
        save()
    }

    private func save() {
        guard let kg = parsedKg else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let entry = editingEntry {
                    try await store.update(entry, kg: kg, date: date)
                } else {
                    try await store.add(kg: kg, date: date)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func delete() {
        guard let entry = editingEntry else { return }
        Task {
            do {
                try await store.delete(entry)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(WeightStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    private var unit: WeightUnit { settings.unit }
    private var parsedKg: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).map { unit.kilograms(from: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Goal", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        Text(unit.symbol).foregroundStyle(.secondary)
                    }
                } footer: {
                    if let current = store.series.trend.last?.kg {
                        Text("Your current trend weight is \(unit.format(current)).")
                    }
                }
                if settings.goalKg != nil {
                    Section {
                        Button("Remove Goal", role: .destructive) {
                            settings.goalKg = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Goal Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.goalKg = parsedKg
                        if !settings.isVisible(.goal) { settings.toggle(.goal) }
                        dismiss()
                    }
                    .disabled(parsedKg.map { !WeightUnit.plausibleKilograms.contains($0) } ?? true)
                }
            }
            .onAppear {
                if let goal = settings.goalKg {
                    text = unit.value(fromKilograms: goal).formatted(.number.precision(.fractionLength(1)).grouping(.never))
                }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}
