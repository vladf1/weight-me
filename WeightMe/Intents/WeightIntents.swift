import AppIntents
import Foundation

enum WeightIntentError: Error, CustomLocalizedStringResourceConvertible {
    case implausible(String)
    case noData

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .implausible(let value): "\(value) doesn't look like a body weight."
        case .noData: "There's no weight data in Apple Health yet."
        }
    }
}

/// "Log my weight in WeightMe" — saves straight to Apple Health without opening the app.
struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Weight"
    static let description = IntentDescription("Saves a weight entry to the Health app.", categoryName: "Weight")

    @Parameter(title: "Weight", requestValueDialog: IntentDialog("What's your weight?"))
    var weight: Measurement<UnitMass>

    @Parameter(title: "Date", description: "Defaults to now.")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$weight)") { \.$date }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Measurement<UnitMass>> {
        let kg = weight.converted(to: .kilograms).value
        let unit = AppDependencies.shared.settings?.unit ?? .pounds
        guard WeightUnit.plausibleKilograms.contains(kg) else {
            throw WeightIntentError.implausible(weight.formatted())
        }
        let when = min(date ?? .now, .now)
        if let store = AppDependencies.shared.store {
            try await store.add(kg: kg, date: when)
        } else {
            try await HealthService.shared.save(kg: kg, date: when)
        }
        return .result(value: weight, dialog: "Logged \(unit.format(kg)).")
    }
}

/// "What's my weight in WeightMe?"
struct GetLatestWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Weight"
    static let description = IntentDescription("Returns your most recent weight and trend from the Health app.", categoryName: "Weight")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Measurement<UnitMass>> {
        guard let store = AppDependencies.shared.store else { throw WeightIntentError.noData }
        await store.refreshOnce()
        guard let latest = store.latest else { throw WeightIntentError.noData }
        let unit = AppDependencies.shared.settings?.unit ?? .pounds
        var message = "Your latest weight is \(unit.format(latest.kg)), \(latest.date.formatted(.relative(presentation: .named)))."
        if let trend = store.series.trend.last {
            message += " Your trend weight is \(unit.format(trend.kg))."
        }
        let measurement = Measurement(value: unit.value(fromKilograms: latest.kg), unit: unit == .pounds ? UnitMass.pounds : UnitMass.kilograms)
        return .result(value: measurement, dialog: IntentDialog(stringLiteral: message))
    }
}

/// Opens the app straight to the "Log Weight" sheet (handy for the Action button).
struct OpenLogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Log Weight"
    static let description = IntentDescription("Opens WeightMe ready to log a weight.", categoryName: "Weight")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDependencies.shared.router?.isAddingEntry = true
        return .result()
    }
}

struct WeightMeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWeightIntent(),
                    phrases: ["Log my weight in \(.applicationName)",
                              "Log weight in \(.applicationName)",
                              "Record my weight in \(.applicationName)"],
                    shortTitle: "Log Weight",
                    systemImageName: "scalemass")
        AppShortcut(intent: GetLatestWeightIntent(),
                    phrases: ["What's my weight in \(.applicationName)",
                              "Get my latest weight from \(.applicationName)"],
                    shortTitle: "Latest Weight",
                    systemImageName: "chart.line.downtrend.xyaxis")
        AppShortcut(intent: OpenLogWeightIntent(),
                    phrases: ["Open \(.applicationName) to log weight"],
                    shortTitle: "Open Log Weight",
                    systemImageName: "plus.circle")
    }
}
