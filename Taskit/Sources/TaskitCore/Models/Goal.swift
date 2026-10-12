import Foundation

public enum GoalStatus: String, Codable, CaseIterable, Identifiable {
    case queued
    case dispatching
    case running
    case waitingOnLimit
    case completed
    case failed
    case skipped

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .queued: return "Queued"
        case .dispatching: return "Sending"
        case .running: return "Running"
        case .waitingOnLimit: return "Waiting"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }
}

public struct Goal: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var prompt: String
    public var status: GoalStatus
    public var sortIndex: Int
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var lastError: String?
    public var agentId: String?
    public var runId: String?
    public var agentURL: String?

    public init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        status: GoalStatus = .queued,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastError: String? = nil,
        agentId: String? = nil,
        runId: String? = nil,
        agentURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.status = status
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastError = lastError
        self.agentId = agentId
        self.runId = runId
        self.agentURL = agentURL
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = prompt.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "Untitled prompt"
        return String(firstLine.prefix(72))
    }
}
