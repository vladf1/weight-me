import SwiftUI

@main
struct WeightMeApp: App {
    @State private var settings: AppSettings
    @State private var store: WeightStore
    @State private var router = AppRouter()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let demo = arguments.contains("-demo") || isTesting
        let settings = AppSettings()
        let store = WeightStore(settings: settings, mode: demo ? .demo : .health)
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        if !demo {
            // Keeps the widget current when another app (e.g. a smart scale) writes a weight.
            HealthService.shared.enableBackgroundDelivery { await store.refreshOnce() }
        }
        AppDependencies.shared.store = store
        AppDependencies.shared.settings = settings
        AppDependencies.shared.router = router
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
                .environment(router)
                .task {
                    await store.start()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-reseedHealth") { await store.reseedHealth() }
                    #endif
                }
                .onOpenURL { router.handle($0) }
        }
    }
}

/// Lets App Intents (which run in the app process) reach the live app state.
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()
    var store: WeightStore?
    var settings: AppSettings?
    var router: AppRouter?
}

enum AppTab: Hashable {
    case summary, history, settings
}

@Observable
final class AppRouter {
    var tab: AppTab = .summary
    var isAddingEntry = false
    var isImporting = false
    var isExporting = false
    var isShowingWidgetGallery = false
    /// File to open straight into the import review (debug hook / future "Open in WeightMe").
    var pendingImportURL: URL?

    init() {
        #if DEBUG
        // Debug launch hooks so screens can be reached without tapping:
        //   -tab history|settings   -openImport /path/to/file.csv   -openAdd
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        switch value(after: "-tab") {
        case "history", "entries": tab = .history
        case "settings": tab = .settings
        default: break
        }
        if let path = value(after: "-openImport") {
            tab = .settings
            pendingImportURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
            isImporting = true
        }
        if args.contains("-openAdd") { isAddingEntry = true }
        if args.contains("-openExport") { tab = .settings; isExporting = true }
        if args.contains("-widgetGallery") { isShowingWidgetGallery = true }
        #endif
    }

    func handle(_ url: URL) {
        guard url.scheme == DeepLink.scheme else { return }
        switch url.host() {
        case "add":
            isAddingEntry = true
        case "history", "entries":
            tab = .history
        case "settings":
            tab = .settings
        default:
            tab = .summary
        }
    }
}
