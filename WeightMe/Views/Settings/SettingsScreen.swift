import SwiftUI

struct SettingsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WeightStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var isEditingGoal = false
    @State private var confirmingRebuild = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var router = router
        Form {
            Section("Units") {
                Picker("Weight unit", selection: $settings.unitPreference) {
                    ForEach(AppSettings.UnitPreference.allCases) { pref in
                        if pref == .health {
                            Text("Same as Health (\(settings.healthUnit.symbol))").tag(pref)
                        } else {
                            Text(pref.title).tag(pref)
                        }
                    }
                }
            }

            Section("Goal") {
                Button {
                    isEditingGoal = true
                } label: {
                    LabeledContent("Goal weight") {
                        Text(settings.goalKg.map { settings.unit.format($0) } ?? "Not set")
                    }
                }
                .foregroundStyle(.primary)
                Picker("Projection", selection: $settings.projectionWindowDays) {
                    ForEach([14, 30, 60, 90], id: \.self) { Text("Last \($0) days").tag($0) }
                }
            }

            Section {
                Picker("Same-day readings", selection: $settings.sameDay) {
                    ForEach(SameDayHandling.allCases) { Text($0.title).tag($0) }
                }
                Picker("Trend smoothing", selection: $settings.trendSmoothing) {
                    Text("Gentle").tag(0.05)
                    Text("Standard").tag(0.1)
                    Text("Responsive").tag(0.2)
                }
            } header: {
                Text("Graph")
            } footer: {
                Text("\(settings.sameDay.detail) The trend line is an exponentially smoothed average (as in The Hacker's Diet) that hides day-to-day water-weight swings.")
            }

            Section {
                Button("Export to CSV…", systemImage: "square.and.arrow.up") { router.isExporting = true }
                Button("Import from CSV…", systemImage: "square.and.arrow.down") { router.isImporting = true }
                NavigationLink {
                    ImportHistoryView()
                } label: {
                    Label("Import History", systemImage: "clock.arrow.circlepath")
                        .badge(store.importHistory.filter { $0.undoneAt == nil }.count)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Import adds weights from a CSV file to Apple Health. Weights already there aren't changed.")
            }

            Section {
                LabeledContent("Readings") {
                    Text(store.entries.count.formatted()).accessibilityIdentifier("readingsCount")
                }
                LabeledContent("Sources", value: store.sources.joined(separator: ", "))
                if let lastSync = store.lastSync {
                    LabeledContent("Last synced") {
                        Text("\(Text(lastSync, style: .relative)) ago")
                    }
                }
                if store.mode == .health {
                    Button("Rebuild Local Cache", systemImage: "arrow.clockwise") { confirmingRebuild = true }
                        // Attached to the button so the popover points at it.
                        .confirmationDialog("Re-read everything from Apple Health?", isPresented: $confirmingRebuild, titleVisibility: .visible) {
                            Button("Rebuild Cache") { store.rebuildCache() }
                        } message: {
                            Text("This only clears WeightMe's local copy. Nothing in Apple Health is changed.")
                        }
                }
                Link(destination: URL(string: "x-apple-health://")!) {
                    Label("Open the Health App", systemImage: "heart.text.square")
                }
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Your weights live in Apple Health. WeightMe keeps a copy on this device so it opens quickly, and picks up new entries from Health as they arrive. To change what WeightMe can access, go to Settings › Health › Data Access & Devices › WeightMe.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("Source on GitHub", destination: URL(string: "https://github.com/vladf1/weight-me")!)
            }

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)   // small centered title, like History
        .sheet(isPresented: $isEditingGoal) { GoalEditorView() }
        .sheet(isPresented: $router.isImporting, onDismiss: { router.pendingImportURL = nil }) {
            ImportFlowView(initialURL: router.pendingImportURL)
                .presentationSizing(.page)
        }
        .sheet(isPresented: $router.isExporting) { ExportView() }
    }
}

struct ImportHistoryView: View {
    @Environment(WeightStore.self) private var store
    @State private var pendingUndo: ImportRecord?
    @State private var message: String?

    var body: some View {
        List {
            if store.importHistory.isEmpty {
                ContentUnavailableView("No Imports Yet", systemImage: "clock.arrow.circlepath")
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            ForEach(store.importHistory) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.fileName).font(.headline).lineLimit(1)
                        Spacer()
                        Text("\(record.count)").font(.headline.monospacedDigit())
                    }
                    Text("\(record.sourceLabel) · imported \(record.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = record.firstDate, let last = record.lastDate {
                        Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let undone = record.undoneAt {
                        Label("Undone \(undone.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Button("Undo Import…", role: .destructive) { pendingUndo = record }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .padding(.top, 2)
                            .confirmationDialog("Remove imported entries?",
                                                isPresented: Binding(get: { pendingUndo?.id == record.id },
                                                                     set: { if !$0 { pendingUndo = nil } }),
                                                titleVisibility: .visible) {
                                Button("Remove \(record.count) Entries from Apple Health", role: .destructive) {
                                    Task {
                                        do {
                                            let removed = try await store.undoImport(record)
                                            message = "Removed \(removed) entries."
                                        } catch {
                                            message = error.localizedDescription
                                        }
                                    }
                                }
                            } message: {
                                Text("Every entry added by importing “\(record.fileName)” will be deleted from Apple Health. Other entries are not affected.")
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Import History")
    }
}
