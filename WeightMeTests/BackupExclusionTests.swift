import Foundation
import Testing
@testable import WeightMe

/// Health data must never end up in iCloud backups (App Review guideline 5.1.3).
@MainActor
struct BackupExclusionTests {
    @Test func localDirectoriesAreExcluded() {
        #expect(LocalStorage.isExcludedFromBackup(LocalStorage.appDirectory))
        #expect(LocalStorage.isExcludedFromBackup(LocalStorage.sharedDirectory))
    }

    @Test func everyHealthFileLivesInAnExcludedDirectory() {
        for url in [WeightStore.cacheURL, SharedStorage.snapshotURL, PrivateData.url] {
            #expect(LocalStorage.isExcludedFromBackup(url.deletingLastPathComponent()), "\(url.path)")
        }
    }

    @Test func writtenFilesAreExcludedEvenAfterAtomicReplace() throws {
        let url = LocalStorage.appDirectory.appending(path: "exclusion-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try LocalStorage.write(Data("one".utf8), to: url)
        #expect(LocalStorage.isExcludedFromBackup(url))
        try LocalStorage.write(Data("two".utf8), to: url)   // atomic write replaces the file
        #expect(LocalStorage.isExcludedFromBackup(url))
    }

    @Test func goalWeightIsNotInUserDefaults() {
        #expect(UserDefaults.standard.object(forKey: "goalKg") == nil || ProcessInfo.processInfo.arguments.contains("-goalKg"))
        #expect(UserDefaults.standard.object(forKey: "importHistory") == nil)
    }
}
