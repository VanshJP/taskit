import Foundation

public enum RunState: String, Codable, Sendable {
    /// Not started, or the queue drained.
    case stopped
    /// Sending prompts one after another.
    case running
    /// User paused: the current prompt finishes, nothing new starts.
    case paused
}

public struct LimitState: Codable, Equatable, Sendable {
    public var resetsAt: Date
    public var message: String
    /// When the limit was hit, for the progress bar.
    public var hitAt: Date?

    public init(resetsAt: Date, message: String, hitAt: Date? = nil) {
        self.resetsAt = resetsAt
        self.message = message
        self.hitAt = hitAt
    }

    /// 0 when the limit was hit, 1 at reset.
    public func progress(at now: Date) -> Double {
        guard let hitAt, resetsAt > hitAt else { return 0 }
        return min(1, max(0, now.timeIntervalSince(hitAt) / resetsAt.timeIntervalSince(hitAt)))
    }
}

/// Everything Taskit persists besides settings.
public struct QueueSnapshot: Codable, Equatable, Sendable {
    public var items: [QueueItem]
    public var runState: RunState
    public var limit: LimitState?
    /// Session that "One thread" mode keeps resuming.
    public var threadSessionId: String?

    public init(
        items: [QueueItem] = [],
        runState: RunState = .stopped,
        limit: LimitState? = nil,
        threadSessionId: String? = nil
    ) {
        self.items = items
        self.runState = runState
        self.limit = limit
        self.threadSessionId = threadSessionId
    }
}

/// What the panel shows, derived from the engine's state.
public enum Phase: Equatable, Sendable {
    case empty
    case idle
    case running
    case waiting
    case paused
    case done
}
