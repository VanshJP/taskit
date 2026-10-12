import Foundation

/// Recognises Claude usage-limit messages and works out when the limit resets.
///
/// Formats seen from Claude Code:
/// - `You've hit your session limit · resets 3:45pm`
/// - `You've hit your weekly limit · resets Mon 12:00am`
/// - `Claude usage limit reached. Your limit will reset at 3pm (America/New_York).`
/// - `Claude AI usage limit reached|1760000000` (epoch seconds)
public enum LimitParser {
    /// Used when a limit is detected but no reset time can be read.
    /// Short on purpose: a retry that is still limited simply waits again.
    public static let fallbackWait: TimeInterval = 30 * 60

    public static func isLimitMessage(_ text: String) -> Bool {
        let t = text.lowercased()
        let phrases = [
            "usage limit", "session limit", "weekly limit", "5-hour limit",
            "rate limit", "hit your limit", "limit reached", "limit will reset"
        ]
        return phrases.contains { t.contains($0) }
    }

    /// Stricter check for text that arrived as a *successful* reply: only the
    /// banner Claude Code prints instead of an answer, never a reply that merely
    /// talks about rate limiting.
    public static func isLimitBanner(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        guard t.count < 300 else { return false }
        let prefixes = [
            "claude ai usage limit reached", "claude usage limit reached",
            "you've hit your session limit", "you've hit your weekly limit",
            "you've hit your usage limit", "you've hit your limit",
            "5-hour limit reached", "session limit reached", "weekly limit reached"
        ]
        return prefixes.contains { t.hasPrefix($0) }
    }

    /// Reset time, if the message names one.
    public static func resetDate(
        in text: String,
        now: Date,
        timeZone: TimeZone = .current
    ) -> Date? {
        if let epoch = epochReset(in: text) { return epoch }
        if let clock = clockReset(in: text, now: now, defaultTimeZone: timeZone) { return clock }
        if let relative = relativeReset(in: text, now: now) { return relative }
        return nil
    }

    // MARK: - Formats

    private static let epochPattern = try! NSRegularExpression(
        pattern: #"limit reached\|(\d{9,11})"#,
        options: [.caseInsensitive]
    )

    private static let clockPattern = try! NSRegularExpression(
        pattern: #"\bresets?\s+(?:at\s+)?(?:(mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s*\(([^)]+)\))?"#,
        options: [.caseInsensitive]
    )

    private static let relativePattern = try! NSRegularExpression(
        pattern: #"\bresets?\s+in\s+(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?"#,
        options: [.caseInsensitive]
    )

    private static func epochReset(in text: String) -> Date? {
        guard let m = epochPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text),
              let seconds = TimeInterval(text[r]) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func clockReset(in text: String, now: Date, defaultTimeZone: TimeZone) -> Date? {
        let range = NSRange(text.startIndex..., in: text)
        for m in clockPattern.matches(in: text, range: range) {
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
            guard let hourText = group(2), var hour = Int(hourText) else { continue }
            let minute = group(3).flatMap(Int.init)
            let meridiem = group(4)?.lowercased()
            // "resets 5 hours" is not a clock time: require am/pm or :mm.
            guard minute != nil || meridiem != nil else { continue }
            if let meridiem {
                guard (1...12).contains(hour) else { continue }
                if meridiem == "pm", hour != 12 { hour += 12 }
                if meridiem == "am", hour == 12 { hour = 0 }
            }
            guard (0...23).contains(hour), (0...59).contains(minute ?? 0) else { continue }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = group(5).flatMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) }
                ?? defaultTimeZone

            var match = DateComponents()
            match.hour = hour
            match.minute = minute ?? 0
            match.second = 0
            if let day = group(1) { match.weekday = weekday(day) }

            return calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
        }
        return nil
    }

    private static func relativeReset(in text: String, now: Date) -> Date? {
        guard let m = relativePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func number(_ i: Int) -> Double? {
            guard let r = Range(m.range(at: i), in: text) else { return nil }
            return Double(text[r])
        }
        let hours = number(1)
        let minutes = number(2)
        guard hours != nil || minutes != nil else { return nil }
        return now.addingTimeInterval((hours ?? 0) * 3600 + (minutes ?? 0) * 60)
    }

    private static func weekday(_ text: String) -> Int? {
        switch text.prefix(3).lowercased() {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return nil
        }
    }
}
