import Foundation

/// Locations shared between the app and its widget extension.
nonisolated enum SharedStorage {
    static let appGroupID = "group.me.fridman.weightme"

    /// App-group container, falling back to the app's own Application Support directory
    /// (e.g. when the app group isn't provisioned yet).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let fallback = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var snapshotURL: URL { LocalStorage.sharedDirectory.appending(path: "widget-snapshot.json") }
}

/// Everything WeightMe writes to disk is either a copy of Apple Health data or health-related
/// (goal weight), and App Review guideline 5.1.3 forbids storing health information in iCloud — which
/// includes iCloud device backups. So all of it lives in directories excluded from backup. Nothing is
/// lost by this: on a restored or new device the app simply re-reads Apple Health.
nonisolated enum LocalStorage {
    /// The app's private, never-backed-up directory.
    static var appDirectory: URL {
        excludedDirectory(URL.applicationSupportDirectory.appending(path: "LocalCache", directoryHint: .isDirectory))
    }

    /// Never-backed-up directory in the app group, shared with the widget.
    static var sharedDirectory: URL {
        excludedDirectory(SharedStorage.containerURL.appending(path: "LocalCache", directoryHint: .isDirectory))
    }

    /// Writes atomically, then marks the new file excluded too. (An atomic write replaces the file, so a
    /// flag set on the old file wouldn't carry over; the directory's flag covers it as well.)
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        excludeFromBackup(url)
    }

    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    private static func excludedDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackup(url)
        return url
    }
}

/// URLs the app understands (widgets and shortcuts use these to deep link).
nonisolated enum DeepLink {
    static let scheme = "weightme"
    static let addEntry = URL(string: "weightme://add")!
    static let summary = URL(string: "weightme://summary")!
    static let history = URL(string: "weightme://history")!
}
