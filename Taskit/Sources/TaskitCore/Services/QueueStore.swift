import Foundation

public protocol QueueStoring {
    func loadSnapshot() -> QueueSnapshot
    func saveSnapshot(_ snapshot: QueueSnapshot)
    func loadSettings() -> RelaySettings
    func saveSettings(_ settings: RelaySettings)
}

/// JSON files under Application Support/Taskit.
public final class FileQueueStore: QueueStoring {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base.appendingPathComponent("Taskit", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    var queueURL: URL { directory.appendingPathComponent("queue.json") }
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    public func loadSnapshot() -> QueueSnapshot {
        load(QueueSnapshot.self, from: queueURL) ?? QueueSnapshot()
    }

    public func saveSnapshot(_ snapshot: QueueSnapshot) {
        save(snapshot, to: queueURL)
    }

    public func loadSettings() -> RelaySettings {
        load(RelaySettings.self, from: settingsURL) ?? .default
    }

    public func saveSettings(_ settings: RelaySettings) {
        save(settings, to: settingsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting the user's queue with an empty one.
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

/// In-memory store for tests and previews.
public final class MemoryQueueStore: QueueStoring {
    public var snapshot: QueueSnapshot
    public var settings: RelaySettings

    public init(snapshot: QueueSnapshot = QueueSnapshot(), settings: RelaySettings = .default) {
        self.snapshot = snapshot
        self.settings = settings
    }

    public func loadSnapshot() -> QueueSnapshot { snapshot }
    public func saveSnapshot(_ snapshot: QueueSnapshot) { self.snapshot = snapshot }
    public func loadSettings() -> RelaySettings { settings }
    public func saveSettings(_ settings: RelaySettings) { self.settings = settings }
}
