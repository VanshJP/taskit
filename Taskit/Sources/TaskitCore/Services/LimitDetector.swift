import Foundation

public struct LimitSignal: Equatable, Sendable {
    public var reason: String
    public var resetAt: Date?

    public init(reason: String, resetAt: Date? = nil) {
        self.reason = reason
        self.resetAt = resetAt
    }
}

public enum LimitDetector {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            #"you've hit your (?:usage|rate) limit"#,
            #"hit your rate limit"#,
            #"rate limit(?:ed)?"#,
            #"usage limit"#,
            #"try again in (?<hours>\d+)\s*hours?"#,
            #"resets? in[:\s]+(?<hours>\d+)\s*hours?(?:\s*(?<minutes>\d+)\s*minutes?)?"#,
            #"resets? (?:at|in) (?<clock>\d{1,2}:\d{2}\s*(?:AM|PM)?)"#,
            #"please wait for your limit to reset in (?<hours>\d+)\s*hours?(?:\s*(?<minutes>\d+)\s*minutes?)?"#
        ]
        return raw.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    public static func detect(in text: String, now: Date = .now) -> LimitSignal? {
        let lowered = text.lowercased()
        let looksLikeLimit = lowered.contains("rate limit")
            || lowered.contains("usage limit")
            || lowered.contains("hit your limit")
            || lowered.contains("you've hit")

        guard looksLikeLimit else { return nil }

        if let resetAt = parseResetDate(from: text, now: now) {
            return LimitSignal(reason: text.trimmingCharacters(in: .whitespacesAndNewlines), resetAt: resetAt)
        }

        return LimitSignal(
            reason: text.trimmingCharacters(in: .whitespacesAndNewlines),
            resetAt: now.addingTimeInterval(SessionClock.defaultWindowSeconds)
        )
    }

    public static func detect(statusCode: Int, body: String, now: Date = .now) -> LimitSignal? {
        if statusCode == 429 {
            return detect(in: body, now: now)
                ?? LimitSignal(reason: "HTTP 429 rate limited", resetAt: now.addingTimeInterval(SessionClock.defaultWindowSeconds))
        }
        return detect(in: body, now: now)
    }

    private static func parseResetDate(from text: String, now: Date) -> Date? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for expression in patterns {
            guard let match = expression.firstMatch(in: text, options: [], range: range) else { continue }

            if let hoursRange = Range(match.range(withName: "hours"), in: text),
               let hours = Double(text[hoursRange]) {
                var total = hours * 3600
                if let minutesRange = Range(match.range(withName: "minutes"), in: text),
                   let minutes = Double(text[minutesRange]) {
                    total += minutes * 60
                }
                return now.addingTimeInterval(total)
            }

            if let clockRange = Range(match.range(withName: "clock"), in: text) {
                let clock = String(text[clockRange])
                if let date = parseClock(clock, relativeTo: now) {
                    return date
                }
            }
        }
        return nil
    }

    private static func parseClock(_ value: String, relativeTo now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = ["h:mm a", "h:mma", "H:mm"]
        for format in formats {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: value.trimmingCharacters(in: .whitespaces)) else { continue }
            var calendar = Calendar.current
            calendar.timeZone = .current
            let parts = calendar.dateComponents([.hour, .minute], from: parsed)
            var target = calendar.dateComponents([.year, .month, .day], from: now)
            target.hour = parts.hour
            target.minute = parts.minute
            target.second = 0
            guard var date = calendar.date(from: target) else { continue }
            if date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return date
        }
        return nil
    }
}
