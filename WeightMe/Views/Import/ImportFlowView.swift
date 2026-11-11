import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Import is deliberately slow and explicit:
/// 1. explain → 2. pick file → 3. review every row (counts, chart, warnings, options) →
/// 4. type the number of entries to confirm → 5. write, with undo afterward.
struct ImportFlowView: View {
    /// When set, skips the intro and opens this file straight into review.
    var initialURL: URL? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings

    enum Phase {
        case intro
        case review(ParsedImportFile, fileName: String)
        case importing(progress: Double)
        case finished(ImportRecord)
        case failed(String, wrote: Int)
    }

    @State private var phase: Phase = .intro
    @State private var isPicking = false
    @State private var parseError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro:
                    intro
                case .review(let file, let fileName):
                    ImportReviewView(file: file, fileName: fileName) { plan in
                        Task { await runImport(plan: plan, file: file, fileName: fileName) }
                    }
                case .importing(let progress):
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .frame(maxWidth: 320)
                        Text("Writing to Apple Health… \(Int(progress * 100))%")
                            .font(.headline)
                            .monospacedDigit()
                        Text("Please keep WeightMe open.")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .interactiveDismissDisabled()
                case .finished(let record):
                    ImportFinishedView(record: record) { dismiss() }
                case .failed(let message, let wrote):
                    ContentUnavailableView {
                        Label("Import Stopped", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("\(message)\n\n\(wrote) entries were written before the error. You can undo them from Settings › Import History.")
                    } actions: {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCancel {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $isPicking,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data],
                          allowsMultipleSelection: false) { result in
                handlePicked(result)
            }
        }
        .interactiveDismissDisabled(isImportingPhase)
        .onAppear {
            if let initialURL, case .intro = phase { load(initialURL) }
        }
    }

    /// No Cancel while writing to Health or once finished (the finished screen has its own Done).
    private var showsCancel: Bool {
        switch phase {
        case .importing, .finished: false
        default: true
        }
    }

    private var isImportingPhase: Bool {
        if case .importing = phase { return true }
        if case .review = phase { return true }    // avoid losing a review with a stray swipe
        return false
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                Text("Import weights from a CSV file")
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 14) {
                    bullet("doc.text", "Works with Lose It! exports (Date, Weight, Last Updated, Deleted) and WeightMe's own exports.")
                    bullet("plus.circle", "Imported weights are **added** to Apple Health as new entries from WeightMe.")
                    bullet("shield.lefthalf.filled", "**Nothing already in Apple Health is changed or overwritten.** Any day that already has a weight in Apple Health is skipped.")
                    bullet("eye", "You'll review every row, see a chart of what will be added, and confirm twice before anything is written.")
                    bullet("arrow.uturn.backward", "Each import can be undone later from Settings › Import History.")
                }
                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding()
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    isPicking = true
                } label: {
                    Label("Choose CSV File…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func handlePicked(_ result: Result<[URL], Error>) {
        parseError = nil
        switch result {
        case .failure(let error):
            parseError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url)
        }
    }

    private func load(_ url: URL) {
        parseError = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let text = CSV.decode(data) else { throw ImportParseError.unreadable }
            let file = try WeightCSVImport.parse(text)
            phase = .review(file, fileName: url.lastPathComponent)
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func runImport(plan: ImportPlan, file: ParsedImportFile, fileName: String) async {
        let readings = plan.toImport.compactMap { row -> (date: Date, kg: Double)? in
            guard let d = row.date, let kg = row.kg else { return nil }
            return (d, kg)
        }
        let batchID = UUID().uuidString
        phase = .importing(progress: 0)
        do {
            _ = try await store.importReadings(readings, batchID: batchID, sourceLabel: file.format.sourceLabel,
                                               fileName: fileName) { progress in
                phase = .importing(progress: progress)
            }
            if let record = store.importHistory.first(where: { $0.id == batchID }) {
                phase = .finished(record)
            } else {
                dismiss()
            }
        } catch {
            let wrote = store.entriesInBatch(batchID)
            if wrote > 0 {
                let dates = store.entries.filter { $0.importBatchID == batchID }.map(\.date)
                let record = ImportRecord(id: batchID, date: .now, fileName: fileName, sourceLabel: file.format.sourceLabel,
                                          count: wrote, firstDate: dates.min(), lastDate: dates.max())
                var history = store.importHistory
                history.insert(record, at: 0)
                ImportRecord.saveAll(history)
            }
            phase = .failed(error.localizedDescription, wrote: wrote)
        }
    }
}

// MARK: - Review

struct ImportReviewView: View {
    let file: ParsedImportFile
    let fileName: String
    let onConfirm: (ImportPlan) -> Void

    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum RowFilter: String, CaseIterable, Identifiable {
        case toImport = "To Import"
        case skipped = "Skipped"
        case problems = "Problems"
        var id: String { rawValue }
    }

    @State private var unit: WeightUnit = .pounds
    @State private var timeOfDay = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
    @State private var dateOrder: DateOrder = .monthFirst
    @State private var reparsed: ParsedImportFile?
    @State private var filter: RowFilter = .toImport
    @State private var didLoad = false
    @State private var showingFinalConfirmation = false

    private var activeFile: ParsedImportFile { reparsed ?? file }

    private var plan: ImportPlan {
        let c = Calendar.current.dateComponents([.hour, .minute], from: timeOfDay)
        return ImportPlan.build(file: activeFile, unit: unit, defaultHour: c.hour ?? 8, defaultMinute: c.minute ?? 0,
                                existing: store.entries)
    }

    var body: some View {
        let plan = self.plan
        List {
            Section {
                LabeledContent("File", value: fileName)
                LabeledContent("Format", value: activeFile.format.title)
                LabeledContent("Rows in file", value: activeFile.rows.count.formatted())
            }

            Section {
                SummaryRow(symbol: "plus.circle.fill", color: .green, title: "Will be added to Apple Health",
                           count: plan.importCount, emphasized: true)
                if let range = plan.importDateRange {
                    Text("\(range.lowerBound.formatted(date: .long, time: .omitted)) – \(range.upperBound.formatted(date: .long, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                SummaryRow(symbol: "checkmark.shield", color: .blue, title: "Skipped — day already in Apple Health",
                           count: plan.existingCount)
                if plan.deletedCount > 0 {
                    SummaryRow(symbol: "trash.slash", color: .secondary, title: "Skipped — marked deleted in Lose It",
                               count: plan.deletedCount)
                }
                if plan.duplicateInFileCount > 0 {
                    SummaryRow(symbol: "doc.on.doc", color: .secondary, title: "Skipped — same day appears twice in file",
                               count: plan.duplicateInFileCount)
                }
                if plan.invalidCount > 0 {
                    SummaryRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Skipped — couldn't read",
                               count: plan.invalidCount)
                }
            } header: {
                Text("Summary")
            } footer: {
                Text("Nothing in Apple Health will be changed or overwritten. Only the green entries are written.")
            }

            if !plan.warnings.isEmpty {
                Section("Please check") {
                    ForEach(plan.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
            }

            Section {
                if !activeFile.unitsSpecified {
                    Picker("Weights in the file are in", selection: $unit) {
                        ForEach(WeightUnit.allCases) { Text($0.name).tag($0) }
                    }
                }
                if activeFile.rows.contains(where: { !$0.hasTime && $0.components != nil }) {
                    DatePicker("Time for date-only rows", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                }
                if activeFile.rows.contains(where: { $0.rawDate.contains("/") || $0.rawDate.contains(".") }) {
                    Picker("Date format", selection: $dateOrder) {
                        ForEach(DateOrder.allCases) { Text($0.title).tag($0) }
                    }
                    if let sample = activeFile.rows.first(where: { $0.components != nil }) {
                        Text("“\(sample.rawDate)” is read as \(sampleDate(sample))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Interpretation")
            } footer: {
                Text("Lose It! exports don't include a unit or time of day. Double-check these before importing.")
            }

            Section("Preview") {
                ImportPreviewChart(plan: plan, existing: store.series.readings, unit: unit)
                    .frame(height: 200)
                    .padding(.vertical, 6)
            }

            Section {
                Picker("Show", selection: $filter) {
                    ForEach(RowFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                let filtered = rows(plan, filter)
                if filtered.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(filtered.prefix(500)) { row in
                    ImportRowView(row: row, unit: unit)
                }
                if filtered.count > 500 {
                    Text("…and \(filtered.count - 500) more")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Rows")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    showingFinalConfirmation = true
                } label: {
                    Text(plan.importCount == 0 ? "Nothing to Import" : "Import \(plan.importCount) Entries…")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(plan.importCount == 0)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingFinalConfirmation) {
            FinalImportConfirmation(plan: plan, unit: unit) {
                showingFinalConfirmation = false
                onConfirm(plan)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            unit = settings.unit
            dateOrder = file.dateOrder
        }
        .onChange(of: dateOrder) { _, newValue in
            guard newValue != file.dateOrder || reparsed != nil else { return }
            reparsed = try? reparse(order: newValue)
        }
    }

    private func reparse(order: DateOrder) throws -> ParsedImportFile {
        // Re-run parsing on the original rows with a forced date order.
        var copy = file
        copy.dateOrder = order
        copy.rows = file.rows.map { row in
            var r = row
            let parsed = WeightCSVImport.parseDate(row.rawDate, order: order)
            r.components = parsed.components
            r.exactDate = parsed.exact
            return r
        }
        return copy
    }

    private func sampleDate(_ row: ParsedImportRow) -> String {
        guard let c = row.components, let date = Calendar.current.date(from: c) else { return "?" }
        return date.formatted(date: .long, time: .omitted)
    }

    private func rows(_ plan: ImportPlan, _ filter: RowFilter) -> [ImportPlan.Row] {
        switch filter {
        case .toImport: plan.rows.filter { $0.status.isImport }
        case .skipped: plan.rows.filter {
            switch $0.status {
            case .existsInHealth, .duplicateInFile, .deletedInSource: true
            default: false
            }
        }
        case .problems: plan.rows.filter { if case .invalid = $0.status { true } else { false } }
        }
    }
}

private struct SummaryRow: View {
    let symbol: String
    let color: Color
    let title: String
    let count: Int
    var emphasized = false

    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            Spacer()
            Text(count.formatted())
                .monospacedDigit()
                .font(emphasized ? .title3.bold() : .body)
                .foregroundStyle(emphasized ? color : .primary)
        }
    }
}

private struct ImportRowView: View {
    let row: ImportPlan.Row
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let date = row.date {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year().hour().minute()))
                } else {
                    Text(row.rawDate.isEmpty ? "(no date)" : row.rawDate)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let kg = row.kg {
                    Text(unit.format(kg)).monospacedDigit().fontWeight(.medium)
                } else {
                    Text(row.rawWeight).foregroundStyle(.secondary)
                }
                Text("line \(row.line)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
    }

    private var statusText: String {
        switch row.status {
        case .willImport: "Will be added"
        case .existsInHealth(let values):
            "Skipped: Apple Health already has \(values.map { unit.format($0) }.joined(separator: ", ")) that day"
        case .duplicateInFile(let kept): "Skipped: same day as line \(kept)"
        case .deletedInSource: "Skipped: marked deleted in Lose It"
        case .invalid(let reason): reason
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .willImport: .green
        case .invalid: .orange
        default: .secondary
        }
    }
}

/// Existing Health data in gray, to-be-imported points in green.
struct ImportPreviewChart: View {
    let plan: ImportPlan
    let existing: [SeriesPoint]
    let unit: WeightUnit

    var body: some View {
        let incoming = plan.toImport.compactMap { row -> SeriesPoint? in
            guard let d = row.date, let kg = row.kg else { return nil }
            return SeriesPoint(date: d, kg: kg)
        }
        let all = existing.map(\.kg) + incoming.map(\.kg)
        let scale = YAxisScale.make(minKg: all.min() ?? 70, maxKg: all.max() ?? 80, unit: unit, targetTicks: 4)
        let existingShown = WeightChartView.decimate(existing[...], maxCount: 800)
        let incomingShown = WeightChartView.decimate(incoming[...], maxCount: 800)
        Chart {
            ForEach(existingShown) { p in
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.kg))
                    .symbolSize(8)
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
            ForEach(incomingShown) { p in
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.kg))
                    .symbolSize(14)
                    .foregroundStyle(Color.green)
            }
        }
        .chartYScale(domain: scale.domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.ticks) { value in
                AxisGridLine()
                AxisValueLabel { if let kg = value.as(Double.self) { Text(unit.format(kg, decimals: 0, includeUnit: false)) } }
            }
        }
        .chartOverlay { _ in
            VStack {
                HStack(spacing: 12) {
                    legend(.gray, "In Apple Health")
                    legend(.green, "Will be added")
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Last gate: the user must type the exact number of entries.
struct FinalImportConfirmation: View {
    let plan: ImportPlan
    let unit: WeightUnit
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces) == String(plan.importCount) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Final check", systemImage: "exclamationmark.shield.fill")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Text("You're about to add **\(plan.importCount) weight entries** to Apple Health.")
                        if let range = plan.importDateRange {
                            Text("Dates: \(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted)). Unit: \(unit.name).")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    TextField("Type \(plan.importCount) to confirm", text: $typed)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .font(.title3.monospacedDigit())
                } footer: {
                    Text("You can undo this import later from Settings › Import History.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Pinned above the keyboard so it's visible while typing the count.
                Button {
                    onConfirm()
                } label: {
                    Text("Add \(plan.importCount) Entries to Apple Health")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .disabled(!matches)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Confirm Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

struct ImportFinishedView: View {
    let record: ImportRecord
    let done: () -> Void

    @Environment(WeightStore.self) private var store
    @State private var confirmingUndo = false
    @State private var undoneCount: Int?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: undoneCount == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(undoneCount == nil ? .green : .orange)
            if let undoneCount {
                Text("Import undone").font(.title2.bold())
                Text("Removed \(undoneCount) entries from Apple Health.").foregroundStyle(.secondary)
            } else {
                Text("Imported \(record.count) entries").font(.title2.bold())
                Text("They're in Apple Health now. You can undo this any time from Settings › Import History.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if undoneCount == nil {
                Button("Undo This Import", role: .destructive) { confirmingUndo = true }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Remove the \(record.count) imported entries from Apple Health?",
                            isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Remove \(record.count) Entries", role: .destructive) {
                Task { undoneCount = try? await store.undoImport(record) }
            }
        }
    }
}
