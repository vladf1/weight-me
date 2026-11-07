import Foundation

/// Locations shared between the app and its widget extension.
nonisolated enum SharedStorage {
    static let appGroupID = "group.com.vladf1.weightme"

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

    static var snapshotURL: URL { containerURL.appending(path: "widget-snapshot.json") }
}

/// URLs the app understands (widgets and shortcuts use these to deep link).
nonisolated enum DeepLink {
    static let scheme = "weightme"
    static let addEntry = URL(string: "weightme://add")!
    static let chart = URL(string: "weightme://chart")!
    static let entries = URL(string: "weightme://entries")!
}
