import Foundation

public enum DurationFormat {
    /// Formats a positive duration as `h:mm:ss` or `mm:ss` without locale overhead.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func remaining(until date: Date?, now: Date = .now) -> TimeInterval {
        guard let date else { return 0 }
        return max(0, date.timeIntervalSince(now))
    }
}
