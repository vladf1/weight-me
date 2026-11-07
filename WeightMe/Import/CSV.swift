import Foundation

/// Minimal RFC 4180 CSV reading/writing (quoted fields, embedded commas/quotes/newlines, CRLF, BOM).
nonisolated enum CSV {
    /// Spreadsheet apps in many locales save "CSV" with semicolons (and decimal commas), or tabs.
    /// The delimiter is whichever of , ; or tab appears most in the first line outside quotes.
    static func detectDelimiter(_ text: String) -> Unicode.Scalar {
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for c in text.unicodeScalars {
            if c == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if c == "\n" || c == "\r" { break }
            if counts[c] != nil { counts[c]! += 1 }
        }
        let best = counts.max { a, b in a.value == b.value ? a.key != "," : a.value < b.value }!
        return best.value > 0 ? best.key : ","
    }

    static func parse(_ text: String, delimiter: Unicode.Scalar? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()
        if pending == "\u{FEFF}" { pending = iterator.next() }   // byte-order mark

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
            row = []
        }

        while let c = pending {
            pending = iterator.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" { field.unicodeScalars.append("\""); pending = iterator.next() } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case delimiter: endField()
                case "\r":
                    if pending == "\n" { pending = iterator.next() }
                    endRow()
                case "\n": endRow()
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func line(_ fields: [String]) -> String { fields.map(escape).joined(separator: ",") }

    /// Decodes file bytes trying the encodings spreadsheet apps commonly produce.
    static func decode(_ data: Data) -> String? {
        for encoding: String.Encoding in [.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: encoding) { return s }
        }
        return nil
    }
}
