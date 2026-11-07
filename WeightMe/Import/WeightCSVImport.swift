import Foundation

/// Which kind of CSV was recognized.
nonisolated enum ImportFormat: String, Sendable {
    case loseIt
    case weightMe
    case dateWeight

    var title: String {
        switch self {
        case .loseIt: "Lose It! export"
        case .weightMe: "WeightMe export"
        case .dateWeight: "Date & weight CSV"
        }
    }

    /// Name stored in Health metadata for imported samples.
    var sourceLabel: String {
        switch self {
        case .loseIt: "Lose It CSV"
        case .weightMe: "WeightMe CSV"
        case .dateWeight: "CSV"
        }
    }
}

/// How ambiguous numeric dates like 03/04/12 are read.
nonisolated enum DateOrder: String, Sendable, CaseIterable, Identifiable {
    case monthFirst, dayFirst
    var id: String { rawValue }
    var title: String { self == .monthFirst ? "Month/Day/Year" : "Day/Month/Year" }
}

/// A row as read from the file, before unit / time-of-day choices are applied.
nonisolated struct ParsedImportRow: Identifiable, Sendable, Equatable {
    var line: Int
    var rawDate: String
    var rawWeight: String
    /// Calendar date (and time, if the file had one).
    var components: DateComponents?
    /// Exact instant, when the file had a full timestamp with a zone (WeightMe exports).
    var exactDate: Date?
    var value: Double?
    /// Unit stated in the row itself or the column header, if any.
    var unit: WeightUnit?
    var isDeletedInSource: Bool
    var lastUpdated: Date?
    var id: Int { line }

    var hasTime: Bool { exactDate != nil || components?.hour != nil }
}

nonisolated struct ParsedImportFile: Sendable {
    var format: ImportFormat
    var rows: [ParsedImportRow]
    var dateOrder: DateOrder
    /// True when every row states its own unit — no need to ask the user.
    var unitsSpecified: Bool
    var headers: [String]
}

nonisolated enum ImportParseError: LocalizedError, Equatable {
    case unreadable
    case empty
    case unrecognizedHeader([String])

    var errorDescription: String? {
        switch self {
        case .unreadable: "The file couldn't be read as text."
        case .empty: "The file has no data rows."
        case .unrecognizedHeader(let headers):
            "Couldn't find “Date” and “Weight” columns. Found: \(headers.joined(separator: ", "))."
        }
    }
}

nonisolated enum WeightCSVImport {

    // MARK: Parsing

    static func parse(_ text: String, dateOrderOverride: DateOrder? = nil) throws -> ParsedImportFile {
        let table = CSV.parse(text)
        guard let header = table.first else { throw ImportParseError.empty }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        func column(_ predicate: (String) -> Bool) -> Int? { normalized.firstIndex(where: predicate) }
        guard let dateCol = column({ $0 == "date" || $0.hasPrefix("date") }),
              let weightCol = column({ $0 == "weight" || $0.hasPrefix("weight") }) else {
            throw ImportParseError.unrecognizedHeader(header)
        }
        let unitCol = column { $0 == "unit" || $0 == "units" }
        let deletedCol = column { $0 == "deleted" }
        let updatedCol = column { $0 == "last updated" || $0 == "lastupdated" || $0 == "updated" }
        let headerUnit = unitIn(normalized[weightCol])

        let format: ImportFormat = unitCol != nil ? .weightMe
            : (deletedCol != nil || updatedCol != nil) ? .loseIt : .dateWeight

        let dataRows = table.dropFirst()
        guard !dataRows.isEmpty else { throw ImportParseError.empty }

        let order = dateOrderOverride ?? detectDateOrder(dataRows.compactMap { $0[safe: dateCol] })

        var rows: [ParsedImportRow] = []
        rows.reserveCapacity(dataRows.count)
        var allHaveUnits = true
        for (offset, fields) in dataRows.enumerated() {
            let rawDate = fields[safe: dateCol]?.trimmingCharacters(in: .whitespaces) ?? ""
            let rawWeight = fields[safe: weightCol]?.trimmingCharacters(in: .whitespaces) ?? ""
            let parsedDate = parseDate(rawDate, order: order)
            let (value, inlineUnit) = parseWeight(rawWeight)
            let unit = unitCol.flatMap { fields[safe: $0] }.flatMap(unitIn) ?? inlineUnit ?? headerUnit
            if unit == nil { allHaveUnits = false }
            let deleted = deletedCol.flatMap { fields[safe: $0] }.map(isTruthy) ?? false
            let updated = updatedCol.flatMap { fields[safe: $0] }.flatMap { parseDate($0, order: order).exact }
            rows.append(ParsedImportRow(line: offset + 2, rawDate: rawDate, rawWeight: rawWeight,
                                        components: parsedDate.components, exactDate: parsedDate.exact,
                                        value: value, unit: unit, isDeletedInSource: deleted, lastUpdated: updated))
        }
        return ParsedImportFile(format: format, rows: rows, dateOrder: order, unitsSpecified: allHaveUnits, headers: header)
    }

    static func isTruthy(_ s: String) -> Bool {
        ["true", "yes", "1", "y", "t"].contains(s.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func unitIn(_ s: String) -> WeightUnit? {
        let t = s.lowercased()
        if t.contains("kg") || t.contains("kilo") { return .kilograms }
        if t.contains("lb") || t.contains("pound") { return .pounds }
        return nil
    }

    /// "236.7", "236,7", "236.7 lb", "107 kg"
    static func parseWeight(_ raw: String) -> (Double?, WeightUnit?) {
        let unit = unitIn(raw)
        var number = raw.lowercased().filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        if !number.contains("."), number.filter({ $0 == "," }).count == 1 {
            number = number.replacingOccurrences(of: ",", with: ".")
        } else {
            number = number.replacingOccurrences(of: ",", with: "")
        }
        return (Double(number), unit)
    }

    // MARK: Dates

    /// If any numeric date has a first field > 12 the file must be day-first; otherwise month-first (US).
    static func detectDateOrder(_ raws: [String]) -> DateOrder {
        var sawFirstOver12 = false
        var sawSecondOver12 = false
        for raw in raws {
            guard let parts = numericDateParts(raw) else { continue }
            if parts.a > 12 { sawFirstOver12 = true }
            if parts.b > 12 { sawSecondOver12 = true }
        }
        return (sawFirstOver12 && !sawSecondOver12) ? .dayFirst : .monthFirst
    }

    private static func numericDateParts(_ raw: String) -> (a: Int, b: Int, y: Int, rest: Substring)? {
        let regex = /^\s*(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{4}|\d{2})(\D.*)?$/
        guard let m = raw.wholeMatch(of: regex), let a = Int(m.1), let b = Int(m.2), let y = Int(m.3) else { return nil }
        return (a, b, y, m.4 ?? "")
    }

    static func parseDate(_ raw: String, order: DateOrder) -> (components: DateComponents?, exact: Date?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, nil) }

        // Full ISO 8601 timestamp with zone, e.g. 2011-08-10T14:03:22Z or 2026-11-07T07:12:00-05:00
        if trimmed.contains("T"), trimmed.count >= 19 {
            let iso = ISO8601DateFormatter()
            for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
                iso.formatOptions = options
                if let date = iso.date(from: trimmed) { return (nil, date) }
            }
        }

        // 2011-07-18, 2011-07-18 08:15, 2011-07-18T08:15:00 (no zone = local)
        let isoLocal = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?$/
        if let m = trimmed.wholeMatch(of: isoLocal) {
            var c = DateComponents(year: Int(m.1), month: Int(m.2), day: Int(m.3))
            if let h = m.4, let mi = m.5 { c.hour = Int(h); c.minute = Int(mi); c.second = m.6.flatMap { Int($0) } ?? 0 }
            return valid(c) ? (c, nil) : (nil, nil)
        }

        // 7/18/11, 07/18/2011, 18.07.2011, optionally followed by a time like "8:15 AM"
        if let parts = numericDateParts(trimmed) {
            let (month, day) = order == .monthFirst ? (parts.a, parts.b) : (parts.b, parts.a)
            var year = parts.y
            if year < 100 {
                let currentYY = Calendar.current.component(.year, from: .now) % 100
                year += year <= currentYY + 1 ? 2000 : 1900
            }
            var c = DateComponents(year: year, month: month, day: day)
            let timeRegex = /^\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?\s*$/
            if let t = parts.rest.wholeMatch(of: timeRegex), var hour = Int(t.1), let minute = Int(t.2) {
                if let ampm = t.4?.lowercased() {
                    if ampm == "pm", hour < 12 { hour += 12 }
                    if ampm == "am", hour == 12 { hour = 0 }
                }
                c.hour = hour; c.minute = minute; c.second = t.3.flatMap { Int($0) } ?? 0
            } else if !parts.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return (nil, nil)
            }
            return valid(c) ? (c, nil) : (nil, nil)
        }
        return (nil, nil)
    }

    private static func valid(_ c: DateComponents) -> Bool {
        guard let y = c.year, let m = c.month, let d = c.day, (1900...2100).contains(y), (1...12).contains(m), (1...31).contains(d) else { return false }
        if let h = c.hour, !(0...23).contains(h) { return false }
        if let mi = c.minute, !(0...59).contains(mi) { return false }
        // Reject impossible dates like Feb 30.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return false }
        return cal.component(.day, from: date) == d
    }
}

// MARK: - Import plan

/// The fully-resolved result of checking a parsed file against what's already in Apple Health.
nonisolated struct ImportPlan: Sendable {
    nonisolated enum Status: Sendable, Equatable {
        case willImport
        case existsInHealth(existingKg: [Double])
        case duplicateInFile(keptLine: Int)
        case deletedInSource
        case invalid(String)

        var isImport: Bool { self == .willImport }
    }

    nonisolated struct Row: Identifiable, Sendable, Equatable {
        var line: Int
        var rawDate: String
        var rawWeight: String
        var date: Date?
        var kg: Double?
        var status: Status
        var id: Int { line }
    }

    var rows: [Row]
    var unit: WeightUnit

    var toImport: [Row] { rows.filter { $0.status.isImport } }
    var importCount: Int { rows.count { $0.status.isImport } }
    var existingCount: Int { rows.count { if case .existsInHealth = $0.status { true } else { false } } }
    var duplicateInFileCount: Int { rows.count { if case .duplicateInFile = $0.status { true } else { false } } }
    var deletedCount: Int { rows.count { $0.status == .deletedInSource } }
    var invalidCount: Int { rows.count { if case .invalid = $0.status { true } else { false } } }

    var importDateRange: ClosedRange<Date>? {
        let dates = toImport.compactMap(\.date)
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        return lo...hi
    }

    /// Plain-language concerns worth showing before the user confirms.
    var warnings: [String] {
        var result: [String] = []
        let values = toImport.compactMap(\.kg).map { unit.value(fromKilograms: $0) }.sorted()
        if !values.isEmpty {
            let median = values[values.count / 2]
            if unit == .kilograms && median > 160 {
                result.append("A typical value here is \(median.formatted(.number.precision(.fractionLength(1)))) kg. If these numbers are really pounds, switch the unit to Pounds.")
            }
            if unit == .pounds && median < 90 {
                result.append("A typical value here is \(median.formatted(.number.precision(.fractionLength(1)))) lb. If these numbers are really kilograms, switch the unit to Kilograms.")
            }
        }
        if invalidCount > 0 {
            result.append("\(invalidCount) row\(invalidCount == 1 ? "" : "s") couldn't be read and will be skipped.")
        }
        return result
    }

    static func build(file: ParsedImportFile, unit: WeightUnit, defaultHour: Int, defaultMinute: Int,
                      existing: [WeightEntry], calendar: Calendar = .current, now: Date = .now) -> ImportPlan {
        var existingByDay: [Date: [Double]] = [:]
        for e in existing { existingByDay[calendar.startOfDay(for: e.date), default: []].append(e.kg) }

        // First pass: individual validation.
        var rows: [Row] = file.rows.map { parsed in
            var row = Row(line: parsed.line, rawDate: parsed.rawDate, rawWeight: parsed.rawWeight, date: nil, kg: nil, status: .willImport)
            if parsed.isDeletedInSource { row.status = .deletedInSource; return row }

            if let exact = parsed.exactDate {
                row.date = exact
            } else if var c = parsed.components {
                if c.hour == nil { c.hour = defaultHour; c.minute = defaultMinute; c.second = 0 }
                row.date = calendar.date(from: c)
            }
            guard let date = row.date else { row.status = .invalid("Unrecognized date “\(parsed.rawDate)”"); return row }
            guard let value = parsed.value else { row.status = .invalid("Unrecognized weight “\(parsed.rawWeight)”"); return row }
            let rowUnit = parsed.unit ?? unit
            let kg = rowUnit.kilograms(from: value)
            row.kg = kg
            guard WeightUnit.plausibleKilograms.contains(kg) else {
                row.status = .invalid("Implausible weight \(rowUnit.format(kg))")
                return row
            }
            guard date <= now.addingTimeInterval(60) else { row.status = .invalid("Date is in the future"); return row }
            if let existingValues = existingByDay[calendar.startOfDay(for: date)] {
                row.status = .existsInHealth(existingKg: existingValues)
            }
            return row
        }

        // Second pass: one reading per day from the file. Keep the most recently updated row
        // (Lose It's "Last Updated"), otherwise the first one in the file.
        var keptByDay: [Date: Int] = [:]   // day -> index into rows
        for i in rows.indices where rows[i].status.isImport {
            guard let date = rows[i].date else { continue }
            let day = calendar.startOfDay(for: date)
            if let keptIndex = keptByDay[day] {
                let keptUpdated = file.rows[keptIndex].lastUpdated ?? .distantPast
                let thisUpdated = file.rows[i].lastUpdated ?? .distantPast
                if thisUpdated > keptUpdated {
                    rows[keptIndex].status = .duplicateInFile(keptLine: rows[i].line)
                    keptByDay[day] = i
                } else {
                    rows[i].status = .duplicateInFile(keptLine: rows[keptIndex].line)
                }
            } else {
                keptByDay[day] = i
            }
        }
        // Re-point duplicates at the final kept row for their day.
        for i in rows.indices {
            if case .duplicateInFile = rows[i].status, let date = rows[i].date,
               let kept = keptByDay[calendar.startOfDay(for: date)] {
                rows[i].status = .duplicateInFile(keptLine: rows[kept].line)
            }
        }
        return ImportPlan(rows: rows, unit: unit)
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
