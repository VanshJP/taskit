import Foundation

public enum DispatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Keep one durable Cloud Agent and send follow-up runs.
    case continueAgent
    /// Start a fresh Cloud Agent for each goal.
    case newAgentEachGoal

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .continueAgent: return "Continue one agent"
        case .newAgentEachGoal: return "New agent per goal"
        }
    }

    public var detail: String {
        switch self {
        case .continueAgent:
            return "Follow-ups keep workspace context under your overarching goal."
        case .newAgentEachGoal:
            return "Each prompt becomes its own Cloud Agent run."
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var overarchingGoal: String
    public var repositoryURL: String
    public var startingRef: String
    public var modelId: String
    public var autoCreatePR: Bool
    public var dispatchMode: DispatchMode
    public var autoContinueOnFinish: Bool
    public var autoResumeOnLimitReset: Bool
    public var sessionFlowPaused: Bool
    public var sessionWindowHours: Double
    public var prependOverarchingGoal: Bool
    public var launchAtLogin: Bool
    public var notifyOnDispatch: Bool
    public var notifyOnComplete: Bool
    public var notifyOnLimit: Bool
    public var activeAgentId: String?

    public init(
        overarchingGoal: String,
        repositoryURL: String,
        startingRef: String,
        modelId: String,
        autoCreatePR: Bool,
        dispatchMode: DispatchMode,
        autoContinueOnFinish: Bool,
        autoResumeOnLimitReset: Bool,
        sessionFlowPaused: Bool = false,
        sessionWindowHours: Double,
        prependOverarchingGoal: Bool,
        launchAtLogin: Bool,
        notifyOnDispatch: Bool,
        notifyOnComplete: Bool,
        notifyOnLimit: Bool,
        activeAgentId: String?
    ) {
        self.overarchingGoal = overarchingGoal
        self.repositoryURL = repositoryURL
        self.startingRef = startingRef
        self.modelId = modelId
        self.autoCreatePR = autoCreatePR
        self.dispatchMode = dispatchMode
        self.autoContinueOnFinish = autoContinueOnFinish
        self.autoResumeOnLimitReset = autoResumeOnLimitReset
        self.sessionFlowPaused = sessionFlowPaused
        self.sessionWindowHours = sessionWindowHours
        self.prependOverarchingGoal = prependOverarchingGoal
        self.launchAtLogin = launchAtLogin
        self.notifyOnDispatch = notifyOnDispatch
        self.notifyOnComplete = notifyOnComplete
        self.notifyOnLimit = notifyOnLimit
        self.activeAgentId = activeAgentId
    }

    public static let `default` = AppSettings(
        overarchingGoal: "",
        repositoryURL: "",
        startingRef: "main",
        modelId: "",
        autoCreatePR: true,
        dispatchMode: .continueAgent,
        autoContinueOnFinish: true,
        autoResumeOnLimitReset: true,
        sessionFlowPaused: false,
        sessionWindowHours: 5,
        prependOverarchingGoal: true,
        launchAtLogin: true,
        notifyOnDispatch: true,
        notifyOnComplete: true,
        notifyOnLimit: true,
        activeAgentId: nil
    )

    public var sessionWindowSeconds: TimeInterval {
        max(15 * 60, sessionWindowHours * 60 * 60)
    }

    public var isConfiguredForDispatch: Bool {
        // Repo is optional (no-repo agents), but an API key is required by the engine separately.
        true
    }

    public func composedPrompt(for goal: Goal) -> String {
        let body = goal.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let umbrella = overarchingGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prependOverarchingGoal, !umbrella.isEmpty else { return body }
        return """
        Overarching goal for this day:
        \(umbrella)

        Next prompt to execute now:
        \(body)
        """
    }

    enum CodingKeys: String, CodingKey {
        case overarchingGoal, repositoryURL, startingRef, modelId
        case autoCreatePR, dispatchMode, autoContinueOnFinish, autoResumeOnLimitReset
        case sessionFlowPaused, sessionWindowHours, prependOverarchingGoal
        case launchAtLogin, notifyOnDispatch, notifyOnComplete, notifyOnLimit, activeAgentId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overarchingGoal = try c.decodeIfPresent(String.self, forKey: .overarchingGoal) ?? ""
        repositoryURL = try c.decodeIfPresent(String.self, forKey: .repositoryURL) ?? ""
        startingRef = try c.decodeIfPresent(String.self, forKey: .startingRef) ?? "main"
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? ""
        autoCreatePR = try c.decodeIfPresent(Bool.self, forKey: .autoCreatePR) ?? true
        dispatchMode = try c.decodeIfPresent(DispatchMode.self, forKey: .dispatchMode) ?? .continueAgent
        autoContinueOnFinish = try c.decodeIfPresent(Bool.self, forKey: .autoContinueOnFinish) ?? true
        autoResumeOnLimitReset = try c.decodeIfPresent(Bool.self, forKey: .autoResumeOnLimitReset) ?? true
        sessionFlowPaused = try c.decodeIfPresent(Bool.self, forKey: .sessionFlowPaused) ?? false
        sessionWindowHours = try c.decodeIfPresent(Double.self, forKey: .sessionWindowHours) ?? 5
        prependOverarchingGoal = try c.decodeIfPresent(Bool.self, forKey: .prependOverarchingGoal) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        notifyOnDispatch = try c.decodeIfPresent(Bool.self, forKey: .notifyOnDispatch) ?? true
        notifyOnComplete = try c.decodeIfPresent(Bool.self, forKey: .notifyOnComplete) ?? true
        notifyOnLimit = try c.decodeIfPresent(Bool.self, forKey: .notifyOnLimit) ?? true
        activeAgentId = try c.decodeIfPresent(String.self, forKey: .activeAgentId)
    }
}
