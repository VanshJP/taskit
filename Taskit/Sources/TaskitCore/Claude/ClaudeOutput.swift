import Foundation

/// Raw result of running the `claude` process.
public struct ProcessOutput: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum FailureKind: Equatable, Sendable {
    case general
    /// Claude Code isn't signed in; every later prompt would fail too.
    case notSignedIn
    /// The `claude` binary couldn't be launched.
    case launch
}

public enum RunOutcome: Equatable, Sendable {
    case success(result: String, sessionId: String?, durationMs: Int?, costUSD: Double?)
    case limited(resetsAt: Date, message: String, sessionId: String?)
    case failed(message: String, sessionId: String?, kind: FailureKind)
    case cancelled
}

/// Turns `claude -p --output-format json` output into a `RunOutcome`.
public enum ClaudeOutputParser {
    struct ResultJSON: Decodable {
        var type: String?
        var subtype: String?
        var is_error: Bool?
        var result: String?
        var session_id: String?
        var duration_ms: Int?
        var total_cost_usd: Double?
        var api_error_status: Int?
    }

    public static func parse(_ output: ProcessOutput, now: Date, timeZone: TimeZone = .current) -> RunOutcome {
        let json = decodeResult(output.stdout)
        let sessionId = json?.session_id

        if let json {
            let isError = json.is_error ?? false
            let subtype = json.subtype ?? "success"
            let result = json.result ?? ""
            if !isError, subtype == "success", !LimitParser.isLimitBanner(result) {
                return .success(
                    result: result.trimmingCharacters(in: .whitespacesAndNewlines),
                    sessionId: sessionId,
                    durationMs: json.duration_ms,
                    costUSD: json.total_cost_usd
                )
            }
            let message = [result, output.stderr]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return classifyFailure(
                message.isEmpty ? describe(subtype: subtype) : message,
                httpStatus: json.api_error_status,
                sessionId: sessionId,
                now: now,
                timeZone: timeZone
            )
        }

        // No JSON result: trust the exit code.
        let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if output.exitCode == 0, !stdout.isEmpty, !LimitParser.isLimitBanner(stdout) {
            return .success(result: stdout, sessionId: nil, durationMs: nil, costUSD: nil)
        }
        return classifyFailure(
            combined.isEmpty ? "Claude Code exited with code \(output.exitCode)." : combined,
            httpStatus: nil,
            sessionId: nil,
            now: now,
            timeZone: timeZone
        )
    }

    static func classifyFailure(
        _ message: String,
        httpStatus: Int?,
        sessionId: String?,
        now: Date,
        timeZone: TimeZone
    ) -> RunOutcome {
        if httpStatus == 429 || LimitParser.isLimitMessage(message) {
            let reset = LimitParser.resetDate(in: message, now: now, timeZone: timeZone)
            let resetsAt = reset.flatMap { $0 > now ? $0 : nil } ?? now.addingTimeInterval(LimitParser.fallbackWait)
            return .limited(resetsAt: resetsAt, message: firstLine(message), sessionId: sessionId)
        }
        if isSignInProblem(message) || httpStatus == 401 {
            return .failed(
                message: "Claude Code isn’t signed in. Run `claude` in Terminal and sign in, then resume.",
                sessionId: sessionId,
                kind: .notSignedIn
            )
        }
        return .failed(message: message, sessionId: sessionId, kind: .general)
    }

    static func isSignInProblem(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("/login")
            || t.contains("not logged in")
            || t.contains("please log in")
            || t.contains("invalid api key")
            || t.contains("oauth token has expired")
    }

    /// The JSON result object: the whole output, or the last line that is one
    /// (in case anything else was printed first).
    static func decodeResult(_ stdout: String) -> ResultJSON? {
        let decoder = JSONDecoder()
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]
        candidates += trimmed
            .split(separator: "\n")
            .reversed()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("{") }
        for candidate in candidates where candidate.hasPrefix("{") {
            if let data = candidate.data(using: .utf8),
               let value = try? decoder.decode(ResultJSON.self, from: data),
               value.type == nil || value.type == "result" {
                return value
            }
        }
        return nil
    }

    private static func describe(subtype: String) -> String {
        switch subtype {
        case "error_max_turns": return "Claude stopped after reaching the maximum number of turns."
        case "error_during_execution": return "Claude Code hit an error while running this prompt."
        case "error_max_budget_usd": return "Claude stopped after reaching the spending limit."
        default: return "Claude Code reported an error (\(subtype))."
        }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? text
    }
}
