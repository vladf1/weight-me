import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum CSVExport {
    static let header = ["Date", "Weight", "Unit", "Source", "Source Bundle ID", "ID"]

    /// WeightMe's own format: one row per reading, local ISO-8601 timestamps with offset.
    static func makeCSV(entries: [WeightEntry], unit: WeightUnit, timeZone: TimeZone = .current) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime]
        var lines = [CSV.line(header)]
        lines.reserveCapacity(entries.count + 1)
        for e in entries {
            let value = (unit.value(fromKilograms: e.kg) * 100).rounded() / 100
            lines.append(CSV.line([
                iso.string(from: e.date),
                value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))),
                unit.symbol,
                e.sourceName,
                e.sourceBundleID,
                e.id.uuidString,
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func fileName(now: Date = .now) -> String {
        "WeightMe-\(now.formatted(.iso8601.year().month().day())).csv"
    }
}

/// FileDocument wrapper for `.fileExporter`.
struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = CSV.decode(data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Transferable CSV for ShareLink.
struct CSVFile: Transferable {
    var text: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.name }
    }
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WeightStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var unit: WeightUnit = .pounds
    @State private var includeOtherApps = true
    @State private var isSaving = false
    @State private var savedMessage: String?
    @State private var didLoad = false

    private var selected: [WeightEntry] {
        includeOtherApps ? store.entries : store.entries.filter(\.isOwn)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Unit", selection: $unit) {
                        ForEach(WeightUnit.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Include entries from other apps", isOn: $includeOtherApps)
                } footer: {
                    Text("Exports every reading with its exact time, value, unit and source. The file can be imported back into WeightMe; days already in Apple Health are skipped.")
                }
                Section {
                    LabeledContent("Entries", value: selected.count.formatted())
                    if let first = selected.first?.date, let last = selected.last?.date {
                        LabeledContent("Dates", value: "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                Section {
                    Button("Save to Files…", systemImage: "folder") { isSaving = true }
                        .disabled(selected.isEmpty)
                    ShareLink(item: CSVFile(text: CSVExport.makeCSV(entries: selected, unit: unit), name: CSVExport.fileName()),
                              preview: SharePreview(CSVExport.fileName(), image: Image(systemName: "tablecells"))) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selected.isEmpty)
                }
                if let savedMessage {
                    Section { Label(savedMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(isPresented: $isSaving,
                          document: CSVDocument(text: CSVExport.makeCSV(entries: selected, unit: unit)),
                          contentType: .commaSeparatedText,
                          defaultFilename: CSVExport.fileName()) { result in
                switch result {
                case .success(let url): savedMessage = "Saved \(url.lastPathComponent)"
                case .failure(let error): savedMessage = error.localizedDescription
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                unit = settings.unit
            }
        }
    }
}
