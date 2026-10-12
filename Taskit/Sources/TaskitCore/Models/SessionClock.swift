import Foundation

public enum SessionPhase: String, Codable, Equatable {
    case idle
    case active
    case cooling
    case ready

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .active: return "In session"
        case .cooling: return "Cooling"
        case .ready: return "Ready"
        }
    }
}

public struct SessionClock: Codable, Equatable {
    /// Default Cursor-style short window many users treat as the overnight gate.
    public static let defaultWindowSeconds: TimeInterval = 5 * 60 * 60

    public var phase: SessionPhase
    public var windowSeconds: TimeInterval
    public var sessionStartedAt: Date?
    public var coolingUntil: Date?
    public var lastLimitReason: String?
    public var consecutiveDispatches: Int

    public init(
        phase: SessionPhase = .idle,
        windowSeconds: TimeInterval = SessionClock.defaultWindowSeconds,
        sessionStartedAt: Date? = nil,
        coolingUntil: Date? = nil,
        lastLimitReason: String? = nil,
        consecutiveDispatches: Int = 0
    ) {
        self.phase = phase
        self.windowSeconds = windowSeconds
        self.sessionStartedAt = sessionStartedAt
        self.coolingUntil = coolingUntil
        self.lastLimitReason = lastLimitReason
        self.consecutiveDispatches = consecutiveDispatches
    }

    public var remainingCooling: TimeInterval {
        guard let coolingUntil else { return 0 }
        return max(0, coolingUntil.timeIntervalSinceNow)
    }

    public var coolingProgress: Double {
        guard phase == .cooling, windowSeconds > 0 else { return 0 }
        let remaining = remainingCooling
        return min(1, max(0, 1 - (remaining / windowSeconds)))
    }

    public var isReadyToDispatch: Bool {
        switch phase {
        case .idle, .active, .ready:
            return true
        case .cooling:
            return remainingCooling <= 0
        }
    }

    public mutating func markActive(at date: Date = .now) {
        phase = .active
        if sessionStartedAt == nil {
            sessionStartedAt = date
        }
        coolingUntil = nil
    }

    public mutating func markLimitHit(
        reason: String?,
        resetAt: Date? = nil,
        at date: Date = .now
    ) {
        phase = .cooling
        lastLimitReason = reason
        if let resetAt {
            coolingUntil = resetAt
            windowSeconds = max(60, resetAt.timeIntervalSince(date))
        } else {
            coolingUntil = date.addingTimeInterval(windowSeconds)
        }
    }

    public mutating func markReady() {
        phase = .ready
        coolingUntil = nil
        lastLimitReason = nil
    }

    public mutating func markIdle() {
        phase = .idle
        sessionStartedAt = nil
        coolingUntil = nil
        lastLimitReason = nil
        consecutiveDispatches = 0
    }

    public mutating func tick(now: Date = .now) -> Bool {
        guard phase == .cooling, let coolingUntil else { return false }
        if now >= coolingUntil {
            markReady()
            return true
        }
        return false
    }
}
