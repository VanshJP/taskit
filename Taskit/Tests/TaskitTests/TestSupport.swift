import Foundation
@testable import TaskitCore

/// Returns scripted outputs in order (then plain successes) and records every invocation.
final class ScriptedRunner: ClaudeRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [ProcessOutput]
    private var recorded: [ClaudeInvocation] = []

    init(_ outputs: [ProcessOutput] = []) {
        self.outputs = outputs
    }

    var invocations: [ClaudeInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ invocation: ClaudeInvocation) async throws -> ProcessOutput {
        lock.lock()
        recorded.append(invocation)
        let next = outputs.isEmpty
            ? success("ok", session: "s\(recorded.count)")
            : outputs.removeFirst()
        lock.unlock()
        return next
    }
}

/// Runs until the calling task is cancelled, like a long Claude run.
struct BlockingRunner: ClaudeRunning {
    func run(_ invocation: ClaudeInvocation) async throws -> ProcessOutput {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return ProcessOutput(exitCode: 143, stdout: "", stderr: "")
    }
}

/// Records requested sleeps and returns immediately.
final class InstantSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var sleep: @Sendable (TimeInterval) async throws -> Void {
        { [self] seconds in
            lock.lock()
            recorded.append(seconds)
            lock.unlock()
        }
    }
}

func resultJSON(
    _ result: String,
    session: String? = "s1",
    isError: Bool = false,
    subtype: String = "success",
    apiStatus: Int? = nil
) -> String {
    var object: [String: Any] = [
        "type": "result",
        "subtype": subtype,
        "is_error": isError,
        "result": result,
        "duration_ms": 1200,
        "total_cost_usd": 0.02
    ]
    if let session { object["session_id"] = session }
    if let apiStatus { object["api_error_status"] = apiStatus }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

func success(_ text: String, session: String = "s1") -> ProcessOutput {
    ProcessOutput(exitCode: 0, stdout: resultJSON(text, session: session), stderr: "")
}

func limited(_ text: String, session: String = "s1") -> ProcessOutput {
    ProcessOutput(exitCode: 1, stdout: resultJSON(text, session: session, isError: true), stderr: "")
}

func failure(_ text: String, session: String = "s1") -> ProcessOutput {
    ProcessOutput(exitCode: 1, stdout: resultJSON(text, session: session, isError: true, subtype: "error_during_execution"), stderr: "")
}

/// 2026-03-04 10:00:00 UTC (a Wednesday).
let referenceNow = Date(timeIntervalSince1970: 1_772_618_400)

let utc = TimeZone(identifier: "UTC")!

func readySettings(_ mode: ConversationMode = .oneThread) -> RelaySettings {
    var settings = RelaySettings.default
    settings.projectPath = "/tmp/taskit-project"
    settings.conversationMode = mode
    settings.setupComplete = true
    return settings
}

let fakeClaude = URL(fileURLWithPath: "/usr/local/bin/claude")
