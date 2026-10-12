import Foundation

public enum DispatchEventKind: String, Codable {
    case dispatched
    case completed
    case failed
    case limitHit
    case resumed
    case skipped
}

public struct DispatchEvent: Identifiable, Codable, Equatable {
    public var id: UUID
    public var kind: DispatchEventKind
    public var message: String
    public var goalId: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: DispatchEventKind,
        message: String,
        goalId: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.goalId = goalId
        self.createdAt = createdAt
    }
}
