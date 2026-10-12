import Foundation

public enum ItemStatus: String, Codable, Sendable {
    case queued
    case running
    /// Was running when a usage limit hit; runs first once the limit resets.
    case waiting
    case done
    case failed
}

public struct QueueItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var prompt: String
    public var status: ItemStatus
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    /// Claude's final reply (success) — shown when the row is expanded.
    public var result: String?
    /// Error or limit message for the last attempt.
    public var error: String?
    /// Claude Code session that ran this prompt, for "Open in Terminal".
    public var sessionId: String?
    public var durationMs: Int?
    public var costUSD: Double?

    public init(
        id: UUID = UUID(),
        prompt: String,
        status: ItemStatus = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
    }

    /// First non-empty line, for one-line rows and notifications.
    public var title: String {
        let line = prompt
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return line.isEmpty ? "Untitled prompt" : line
    }

    public var isPending: Bool { status == .queued || status == .waiting }
    public var isFinished: Bool { status == .done || status == .failed }
}
