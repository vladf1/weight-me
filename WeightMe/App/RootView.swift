import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WeightStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        Group {
            switch store.status {
            case .needsAuthorization:
                OnboardingView()
            case .unavailable:
                ContentUnavailableView("Apple Health Unavailable", systemImage: "heart.slash",
                                       description: Text("This device doesn't support Apple Health, which WeightMe uses to store your weight."))
            default:
                MainTabs()
            }
        }
        .sheet(isPresented: $router.isAddingEntry) {
            EntryEditorView(mode: .add)
        }
        #if DEBUG
        .fullScreenCover(isPresented: $router.isShowingWidgetGallery) { WidgetGalleryView() }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resume() }
        }
        .onChange(of: settings.sameDay) { store.recomputeSeries() }
        .onChange(of: settings.trendSmoothing) { store.recomputeSeries() }
        .onChange(of: settings.unit) { store.settingsAffectingWidgetChanged() }
        .onChange(of: settings.goalKg) { store.settingsAffectingWidgetChanged() }
    }
}

struct MainTabs: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Summary", systemImage: "scalemass", value: AppTab.summary) {
                NavigationStack { SummaryScreen() }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryScreen() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsScreen() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Toolbar button used on several screens to log a new weight.
struct AddEntryButton: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        Button {
            router.isAddingEntry = true
        } label: {
            Label("Log Weight", systemImage: "plus")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}
