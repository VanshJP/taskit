import Foundation

public enum ConversationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Every prompt resumes the same Claude Code session.
    case oneThread
    /// Every prompt starts a new session.
    case fresh

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .oneThread: return "One thread"
        case .fresh: return "Fresh each time"
        }
    }

    public var detail: String {
        switch self {
        case .oneThread: return "Each prompt continues the same Claude conversation."
        case .fresh: return "Each prompt starts a new Claude conversation."
        }
    }
}

public struct RelaySettings: Codable, Equatable, Sendable {
    /// Folder Claude Code runs in. Empty until the user picks one.
    public var projectPath: String
    public var conversationMode: ConversationMode
    /// Run with `--permission-mode auto` so nothing stops to ask.
    public var autoMode: Bool
    /// Optional `--model` value; empty uses Claude Code's default.
    public var model: String
    /// Optional explicit path to the `claude` binary; empty means auto-detect.
    public var claudePath: String
    public var keepAwake: Bool
    public var launchAtLogin: Bool
    public var notifyEachPrompt: Bool
    public var notifyLimit: Bool
    public var notifyQueueDone: Bool
    /// Set once the first-run checklist has been completed.
    public var setupComplete: Bool

    public static let `default` = RelaySettings(
        projectPath: "",
        conversationMode: .oneThread,
        autoMode: true,
        model: "",
        claudePath: "",
        keepAwake: true,
        launchAtLogin: false,
        notifyEachPrompt: false,
        notifyLimit: true,
        notifyQueueDone: true,
        setupComplete: false
    )

    public init(
        projectPath: String,
        conversationMode: ConversationMode,
        autoMode: Bool,
        model: String,
        claudePath: String,
        keepAwake: Bool,
        launchAtLogin: Bool,
        notifyEachPrompt: Bool,
        notifyLimit: Bool,
        notifyQueueDone: Bool,
        setupComplete: Bool
    ) {
        self.projectPath = projectPath
        self.conversationMode = conversationMode
        self.autoMode = autoMode
        self.model = model
        self.claudePath = claudePath
        self.keepAwake = keepAwake
        self.launchAtLogin = launchAtLogin
        self.notifyEachPrompt = notifyEachPrompt
        self.notifyLimit = notifyLimit
        self.notifyQueueDone = notifyQueueDone
        self.setupComplete = setupComplete
    }

    /// Tolerates missing keys so adding a setting never wipes the file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RelaySettings.default
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath) ?? d.projectPath
        conversationMode = try c.decodeIfPresent(ConversationMode.self, forKey: .conversationMode) ?? d.conversationMode
        autoMode = try c.decodeIfPresent(Bool.self, forKey: .autoMode) ?? d.autoMode
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? d.claudePath
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? d.keepAwake
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        notifyEachPrompt = try c.decodeIfPresent(Bool.self, forKey: .notifyEachPrompt) ?? d.notifyEachPrompt
        notifyLimit = try c.decodeIfPresent(Bool.self, forKey: .notifyLimit) ?? d.notifyLimit
        notifyQueueDone = try c.decodeIfPresent(Bool.self, forKey: .notifyQueueDone) ?? d.notifyQueueDone
        setupComplete = try c.decodeIfPresent(Bool.self, forKey: .setupComplete) ?? d.setupComplete
    }

    public var projectURL: URL? {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Short folder name for the panel header.
    public var projectName: String {
        projectURL?.lastPathComponent ?? "No folder"
    }

    /// Folder path with the home directory abbreviated to `~`.
    public var projectDisplayPath: String {
        guard let url = projectURL else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
