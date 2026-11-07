import SwiftUI

@main
struct WeightMeWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(model)
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
        }
    }
}

/// Current weight and a button to log a new one.
struct HomeView: View {
    @Environment(WatchModel.self) private var model
    @State private var isLogging = ProcessInfo.processInfo.arguments.contains("-openLog")

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .needsAuthorization:
                ScrollView {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.pink)
                        Text("WeightMe keeps your weight in Apple Health.")
                            .multilineTextAlignment(.center)
                        Button("Connect Health") { Task { await model.connect() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            case .unavailable:
                Text("Apple Health isn't available on this watch.")
                    .multilineTextAlignment(.center)
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                    Button("Try Again") { Task { await model.start() } }
                }
            case .ready:
                current
            }
        }
        .navigationTitle("WeightMe")
        .navigationDestination(isPresented: $isLogging) { LogWeightView() }
    }

    private var current: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if let latest = model.latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(model.unit.format(latest.kg, includeUnit: false))
                        .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(model.unit.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(latest.date, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No weight yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                isLogging = true
            } label: {
                Label("Log Weight", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Pick a weight with the Digital Crown (0.1 steps), starting from the last one, and save it.
struct LogWeightView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var value = 0.0
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    private var unit: WeightUnit { model.unit }
    private var range: ClosedRange<Double> {
        unit.value(fromKilograms: WeightUnit.plausibleKilograms.lowerBound)...unit.value(fromKilograms: WeightUnit.plausibleKilograms.upperBound)
    }
    /// Crown steps accumulate floating-point error; always work with one decimal.
    private var rounded: Double { (value * 10).rounded() / 10 }

    var body: some View {
        VStack(spacing: 6) {
            if let latest = model.latest {
                let delta = unit.kilograms(from: rounded) - latest.kg
                Text("\(unit.formatDelta(delta)) since last")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                stepButton("minus", -0.1)
                VStack(spacing: -2) {
                    Text(rounded.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: rounded))
                    Text(unit.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .focusable()
                .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound, by: 0.1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Weight")
                .accessibilityValue("\(rounded.formatted(.number.precision(.fractionLength(1)))) \(unit.name)")
                stepButton("plus", 0.1)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Button {
                save()
            } label: {
                if saved {
                    Label("Saved", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isSaving || saved)
        }
        .navigationTitle("Log Weight")
        .sensoryFeedback(.success, trigger: saved)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let startKg = model.latest?.kg ?? (unit == .pounds ? WeightUnit.pounds.kilograms(from: 170) : 75)
            value = (unit.value(fromKilograms: startKg) * 10).rounded() / 10
        }
    }

    private func stepButton(_ symbol: String, _ delta: Double) -> some View {
        Button {
            value = min(max(rounded + delta, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(width: 34)
        .accessibilityLabel(delta > 0 ? "Increase" : "Decrease")
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.log(kg: unit.kilograms(from: rounded))
                saved = true
                try? await Task.sleep(for: .seconds(0.8))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
