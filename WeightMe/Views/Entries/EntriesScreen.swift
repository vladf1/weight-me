import SwiftUI

/// One row of the entries table, with values precomputed for sorting.
nonisolated struct EntryRow: Identifiable, Hashable, Sendable {
    let entry: WeightEntry
    /// Change from the previous reading (nil for the first).
    let deltaKg: Double?
    var id: UUID { entry.id }
    var date: Date { entry.date }
    var kg: Double { entry.kg }
    var sourceName: String { entry.sourceName }
    var deltaSortValue: Double { deltaKg ?? 0 }
}

struct EntriesScreen: View {
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var sourceFilter: String?
    @State private var searchText = ""
    @State private var editing: WeightEntry?
    @State private var viewing: WeightEntry?
    @State private var pendingDelete: WeightEntry?
    @State private var isExporting = false
    @State private var sortOrder = [KeyPathComparator(\EntryRow.date, order: .reverse)]
    @State private var selection = Set<EntryRow.ID>()

    private var unit: WeightUnit { settings.unit }

    private var rows: [EntryRow] {
        var previous: WeightEntry?
        var result: [EntryRow] = []
        result.reserveCapacity(store.entries.count)
        for entry in store.entries {
            let row = EntryRow(entry: entry, deltaKg: previous.map { entry.kg - $0.kg })
            previous = entry
            if let sourceFilter, entry.sourceName != sourceFilter { continue }
            result.append(row)
        }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            result = result.filter { row in
                row.entry.sourceName.lowercased().contains(needle)
                    || row.date.formatted(date: .abbreviated, time: .omitted).lowercased().contains(needle)
                    || unit.format(row.kg, includeUnit: false).contains(needle)
            }
        }
        return result
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView("No Entries", systemImage: "list.bullet.rectangle",
                                       description: Text("Weights you log or import, and those from other apps in Apple Health, appear here."))
            } else if horizontalSizeClass == .regular {
                table
            } else {
                list
            }
        }
        .navigationTitle("Entries")
        .searchable(text: $searchText, prompt: "Date, weight or source")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AddEntryButton() }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("Source", selection: $sourceFilter) {
                        Text("All Sources").tag(String?.none)
                        ForEach(store.sources, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Label("Filter", systemImage: sourceFilter == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Export CSV", systemImage: "square.and.arrow.up") { isExporting = true }
            }
        }
        .sheet(item: $editing) { EntryEditorView(mode: .edit($0)) }
        .sheet(item: $viewing) { EntryDetailView(entry: $0) }
        .sheet(isPresented: $isExporting) { ExportView() }
        .confirmationDialog("Delete this entry from Apple Health?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { entry in
            Button("Delete \(unit.format(entry.kg))", role: .destructive) {
                Task { try? await store.delete(entry) }
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: Compact list

    private var list: some View {
        let grouped = Dictionary(grouping: rows) { Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        let months = grouped.keys.sorted(by: >)
        return List {
            if let sourceFilter {
                Section {
                    Label("Showing only \(sourceFilter)", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(months, id: \.self) { month in
                let monthRows = grouped[month]!.sorted { $0.date > $1.date }
                Section {
                    ForEach(monthRows) { row in
                        EntryListRow(row: row, unit: unit)
                            .contentShape(Rectangle())
                            .onTapGesture { open(row.entry) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if row.entry.isOwn {
                                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = row.entry }
                                    Button("Edit", systemImage: "pencil") { editing = row.entry }
                                        .tint(.blue)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        let mean = monthRows.map(\.kg).reduce(0, +) / Double(monthRows.count)
                        Text("avg \(unit.format(mean))").monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Regular-width table

    private var table: some View {
        let sorted = rows.sorted(using: sortOrder)
        return Table(sorted, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { row in
                Text(row.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
            }
            .width(min: 150, ideal: 190)
            TableColumn("Time", value: \.date) { row in
                Text(row.date.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Weight (\(unit.symbol))", value: \.kg) { row in
                Text(unit.format(row.kg, includeUnit: false))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Change", value: \.deltaSortValue) { row in
                if let delta = row.deltaKg {
                    DeltaText(kg: delta, unit: unit)
                }
            }
            .width(min: 70, ideal: 90)
            TableColumn("Source", value: \.sourceName) { row in
                SourceLabel(entry: row.entry)
            }
        }
        .contextMenu(forSelectionType: EntryRow.ID.self) { ids in
            if let id = ids.first, let entry = store.entries.first(where: { $0.id == id }) {
                if entry.isOwn {
                    Button("Edit", systemImage: "pencil") { editing = entry }
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                } else {
                    Button("Details", systemImage: "info.circle") { viewing = entry }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = store.entries.first(where: { $0.id == id }) { open(entry) }
        }
    }

    private func open(_ entry: WeightEntry) {
        if entry.isOwn { editing = entry } else { viewing = entry }
    }
}

struct EntryListRow: View {
    let row: EntryRow
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(unit.format(row.kg))
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(row.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let delta = row.deltaKg { DeltaText(kg: delta, unit: unit).font(.subheadline) }
                SourceLabel(entry: row.entry).font(.caption2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DeltaText: View {
    let kg: Double
    let unit: WeightUnit
    var body: some View {
        let v = (unit.value(fromKilograms: kg) * 10).rounded() / 10
        Text(unit.formatDelta(kg, includeUnit: false))
            .monospacedDigit()
            .foregroundStyle(v < 0 ? Color.green : v > 0 ? Color.orange : Color.secondary)
    }
}

struct SourceLabel: View {
    let entry: WeightEntry
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.isOwn ? (entry.importBatchID != nil ? "square.and.arrow.down" : "pencil") : "lock")
                .imageScale(.small)
            Text(entry.sourceName)
        }
        .foregroundStyle(.secondary)
    }
}

/// Read-only details for entries written by other apps.
struct EntryDetailView: View {
    let entry: WeightEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Weight", value: settings.unit.format(entry.kg, decimals: 2))
                LabeledContent("Date", value: entry.date.formatted(date: .long, time: .shortened))
                LabeledContent("Source", value: entry.sourceName)
                LabeledContent("App ID", value: entry.sourceBundleID)
                Section {
                    Label("Apple Health only lets the app that created an entry change or delete it. To change this one, use \(entry.sourceName) or the Health app (Browse › Body Measurements › Weight › Show All Data).",
                          systemImage: "lock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
