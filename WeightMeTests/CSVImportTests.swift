import Foundation
import Testing
@testable import WeightMe

@MainActor
struct CSVParsingTests {
    @Test func parsesQuotedFieldsAndCRLF() {
        let rows = CSV.parse("a,b,c\r\n\"x, y\",\"he said \"\"hi\"\"\",3\r\n\r\n4,5,6")
        #expect(rows == [["a", "b", "c"], ["x, y", "he said \"hi\"", "3"], ["4", "5", "6"]])
    }

    @Test func stripsByteOrderMark() {
        #expect(CSV.parse("\u{FEFF}Date,Weight\n1/2/12,200")[0] == ["Date", "Weight"])
    }

    @Test func escapeRoundTrips() {
        let fields = ["plain", "with,comma", "with \"quote\"", "multi\nline"]
        #expect(CSV.parse(CSV.line(fields)) == [fields])
    }
}

@MainActor
struct LoseItImportTests {
    let loseIt = """
    Date,Weight,Last Updated,Deleted
    7/18/11,236.7,2011-08-10T14:03:22Z,FALSE
    7/22/11,229.9,2011-07-22T12:00:00Z,FALSE
    7/23/11,229.4,2011-07-23T12:00:00Z,TRUE
    8/1/11,228,2011-08-01T12:00:00Z,FALSE
    8/1/11,227.5,2011-08-02T12:00:00Z,FALSE
    13/45/11,200,2011-08-01T12:00:00Z,FALSE
    1/6/12,abc,2012-01-06T12:00:00Z,FALSE
    """

    @Test func detectsLoseItFormat() throws {
        let file = try WeightCSVImport.parse(loseIt)
        #expect(file.format == .loseIt)
        #expect(file.rows.count == 7)
        #expect(file.dateOrder == .monthFirst)
        #expect(!file.unitsSpecified)
        #expect(file.rows[0].components == DateComponents(year: 2011, month: 7, day: 18))
        #expect(file.rows[0].value == 236.7)
        #expect(file.rows[2].isDeletedInSource)
        #expect(file.rows[0].line == 2)
    }

    @Test func planSkipsDeletedInvalidAndExistingDays() throws {
        let file = try WeightCSVImport.parse(loseIt)
        let calendar = Calendar.current
        let existingDate = calendar.date(from: DateComponents(year: 2011, month: 7, day: 22, hour: 6))!
        let existing = [WeightEntry(date: existingDate, kg: 104, sourceName: "Lose It!", sourceBundleID: "x", isOwn: false)]
        let plan = ImportPlan.build(file: file, unit: .pounds, defaultHour: 8, defaultMinute: 0, existing: existing,
                                    now: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)

        #expect(plan.importCount == 2)         // 7/18 and the later-updated 8/1 row
        #expect(plan.existingCount == 1)        // 7/22 already in Health
        #expect(plan.deletedCount == 1)         // 7/23 deleted in Lose It
        #expect(plan.duplicateInFileCount == 1) // first 8/1 row
        #expect(plan.invalidCount == 2)         // bad date, bad weight

        let kept = plan.rows.first { $0.line == 6 }!
        #expect(kept.status == .willImport)
        #expect(plan.rows.first { $0.line == 5 }!.status == .duplicateInFile(keptLine: 6))

        let first = plan.toImport.first!
        #expect(abs(first.kg! - 236.7 * WeightUnit.kilogramsPerPound) < 1e-9)
        #expect(calendar.component(.hour, from: first.date!) == 8)
    }

    @Test func warnsWhenUnitLooksWrong() throws {
        let file = try WeightCSVImport.parse(loseIt)
        let plan = ImportPlan.build(file: file, unit: .kilograms, defaultHour: 8, defaultMinute: 0, existing: [])
        #expect(plan.warnings.contains { $0.contains("pounds") })
    }

    @Test func rejectsImplausibleAndFutureValues() throws {
        let file = try WeightCSVImport.parse("Date,Weight\n2020-01-01,2367\n2099-01-01,180\n2020-01-02,180")
        let plan = ImportPlan.build(file: file, unit: .pounds, defaultHour: 8, defaultMinute: 0, existing: [])
        #expect(plan.invalidCount == 2)
        #expect(plan.importCount == 1)
    }

    @Test func detectsDayFirstDates() throws {
        let file = try WeightCSVImport.parse("Date,Weight\n18/07/2011,100\n03/08/2011,99")
        #expect(file.dateOrder == .dayFirst)
        #expect(file.rows[1].components == DateComponents(year: 2011, month: 8, day: 3))
    }

    @Test func parsesFourDigitYearsAndTimes() {
        #expect(WeightCSVImport.parseDate("07/18/2011", order: .monthFirst).components == DateComponents(year: 2011, month: 7, day: 18))
        let withTime = WeightCSVImport.parseDate("7/18/2011 8:15 PM", order: .monthFirst).components
        #expect(withTime?.hour == 20)
        #expect(withTime?.minute == 15)
        #expect(WeightCSVImport.parseDate("7/18/20115", order: .monthFirst).components == nil)
        #expect(WeightCSVImport.parseDate("2011-07-18", order: .monthFirst).components == DateComponents(year: 2011, month: 7, day: 18))
    }

    @Test func unrecognizedHeaderThrows() {
        #expect(throws: ImportParseError.self) { try WeightCSVImport.parse("Foo,Bar\n1,2") }
    }

    @Test func parsesWeightVariants() {
        #expect(WeightCSVImport.parseWeight("236.7").0 == 236.7)
        #expect(WeightCSVImport.parseWeight("107,5").0 == 107.5)
        #expect(WeightCSVImport.parseWeight("1,236.5").0 == 1236.5)
        #expect(WeightCSVImport.parseWeight("80 kg").1 == .kilograms)
        #expect(WeightCSVImport.parseWeight("180 lbs").1 == .pounds)
    }

    @Test func rejectsImpossibleCalendarDates() {
        #expect(WeightCSVImport.parseDate("2/30/12", order: .monthFirst).components == nil)
        #expect(WeightCSVImport.parseDate("2/29/12", order: .monthFirst).components != nil)
    }
}

@MainActor
struct ExportRoundTripTests {
    @Test func exportThenImportIsAllDuplicates() throws {
        let entries = DemoData.entries(endingAt: Date(timeIntervalSince1970: 1_780_000_000)).suffix(50).map { $0 }
        let csv = CSVExport.makeCSV(entries: entries, unit: .pounds)
        let file = try WeightCSVImport.parse(csv)
        #expect(file.format == .weightMe)
        #expect(file.unitsSpecified)
        #expect(file.rows.count == entries.count)
        // Times survive exactly (to the second).
        #expect(file.rows[0].exactDate.map { abs($0.timeIntervalSince(entries[0].date)) < 1 } == true)
        let plan = ImportPlan.build(file: file, unit: .kilograms, defaultHour: 8, defaultMinute: 0, existing: entries)
        #expect(plan.importCount == 0)
        // Units come from the file, not the picker, so values round-trip to within 0.01 lb.
        let reimport = ImportPlan.build(file: file, unit: .kilograms, defaultHour: 8, defaultMinute: 0, existing: [])
        let firstKg = try #require(reimport.rows.first?.kg)
        #expect(abs(firstKg - entries[0].kg) < 0.01 * WeightUnit.kilogramsPerPound)
    }
}

/// Files that went through Excel or Numbers before being imported.
@MainActor
struct SpreadsheetResaveTests {
    @Test func semicolonFileWithDecimalCommas() throws {
        let text = "Date;Weight;Last Updated;Deleted\r\n18.07.2011;\"107,4\";2011-07-18T12:00:00Z;FALSE\r\n19.07.2011;106,9;2011-07-19T12:00:00Z;FALSE\r\n"
        let file = try WeightCSVImport.parse(text)
        #expect(file.format == .loseIt)
        #expect(file.rows.count == 2)
        #expect(file.rows[0].value == 107.4)
        #expect(file.rows[1].value == 106.9)
        #expect(file.dateOrder == .dayFirst)
        #expect(file.rows[1].components == DateComponents(year: 2011, month: 7, day: 19))
    }

    @Test func tabSeparatedFile() throws {
        let file = try WeightCSVImport.parse("Date\tWeight\n7/18/11\t236.7\n")
        #expect(file.rows.first?.value == 236.7)
    }

    @Test func commasStillWinWhenFieldsContainSemicolons() {
        #expect(CSV.detectDelimiter("Date,Weight,Note\n1/2/12,200,\"a;b;c\"") == ",")
        #expect(CSV.parse("a,\"x;y\",c")[0] == ["a", "x;y", "c"])
    }

    @Test func excelMidnightMeansDateOnly() throws {
        let file = try WeightCSVImport.parse("Date,Weight\n7/18/2011 0:00,236.7\n2011-07-19 00:00:00,236.1\n7/20/2011 12:00 AM,235.9\n")
        #expect(file.rows[0].components?.hour == nil)
        #expect(file.rows[1].components?.hour == nil)
        #expect(file.rows[2].components?.hour == 0)   // an explicit AM/PM time is kept
        let plan = ImportPlan.build(file: file, unit: .pounds, defaultHour: 8, defaultMinute: 0, existing: [])
        #expect(Calendar.current.component(.hour, from: try #require(plan.rows[0].date)) == 8)
    }
}
