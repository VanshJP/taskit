import Foundation

public enum PersistKey: String, Hashable, Sendable {
    case goals
    case settings
    case session
    case events
}

public enum Persistence {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Compact on-disk JSON — faster encode/write, less memory than prettyPrinted.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Taskit", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static var goalsURL: URL { root.appendingPathComponent("goals.json") }
    public static var settingsURL: URL { root.appendingPathComponent("settings.json") }
    public static var sessionURL: URL { root.appendingPathComponent("session.json") }
    public static var eventsURL: URL { root.appendingPathComponent("events.json") }

    public static func url(for key: PersistKey) -> URL {
        switch key {
        case .goals: return goalsURL
        case .settings: return settingsURL
        case .session: return sessionURL
        case .events: return eventsURL
        }
    }

    public static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
