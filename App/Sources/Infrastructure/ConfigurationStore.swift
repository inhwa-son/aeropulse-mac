import Foundation

enum ConfigurationLoadSource: Equatable, Sendable {
    case primary
    case backupRecovered
    case defaults
}

struct ConfigurationLoadResult: Sendable {
    let settings: AppSettings
    let source: ConfigurationLoadSource
}

actor ConfigurationStore {
    private let fileURL: URL
    private let backupFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        let appSupport = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("AeroPulse", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("settings.json")
        backupFileURL = directory.appendingPathComponent("settings.json.bak")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() async -> ConfigurationLoadResult {
        if let settings = loadSettings(from: fileURL) {
            return ConfigurationLoadResult(settings: settings, source: .primary)
        }

        if let settings = loadSettings(from: backupFileURL) {
            if let backupData = try? Data(contentsOf: backupFileURL) {
                try? backupData.write(to: fileURL, options: [.atomic])
            }
            return ConfigurationLoadResult(settings: settings, source: .backupRecovered)
        }

        return ConfigurationLoadResult(settings: .default, source: .defaults)
    }

    func save(_ settings: AppSettings) async throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
        try data.write(to: backupFileURL, options: [.atomic])
    }

    private func loadSettings(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return nil
        }

        return settings
    }
}
