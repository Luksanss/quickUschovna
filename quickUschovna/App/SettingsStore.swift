import Foundation
import os

/// What the app keeps between launches: the sender's address and the sent links. Both stay on this
/// Mac; nothing is synced.
final class SettingsStore {
    static let standard = SettingsStore(
        defaults: .standard,
        historyURL: URL.applicationSupportDirectory
            .appending(path: "quickUschovna", directoryHint: .isDirectory)
            .appending(path: "history.json")
    )

    private let defaults: UserDefaults
    private let historyURL: URL
    private let logger = Logger(subsystem: "com.luksanss.quickUschovna", category: "settings")
    private static let senderEmailKey = "senderEmail"

    init(defaults: UserDefaults, historyURL: URL) {
        self.defaults = defaults
        self.historyURL = historyURL
    }

    var senderEmail: String? {
        get { defaults.string(forKey: Self.senderEmailKey) }
        set { defaults.set(newValue, forKey: Self.senderEmailKey) }
    }

    func loadHistory() -> [LinkRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        do {
            return try JSONDecoder().decode([LinkRecord].self, from: data)
        } catch {
            logger.error("Couldn't read the history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Saves the links that are still valid; expired ones are gone from Úschovna anyway.
    func saveHistory(_ history: [LinkRecord]) {
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history.filter { $0.isValid() })
            try data.write(to: historyURL, options: .atomic)
        } catch {
            logger.error("Couldn't save the history: \(String(describing: error), privacy: .public)")
        }
    }
}
