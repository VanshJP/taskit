import XCTest
@testable import TaskitCore

final class LimitParserTests: XCTestCase {
    private func date(_ text: String) -> Date? {
        LimitParser.resetDate(in: text, now: referenceNow, timeZone: utc)
    }

    func testSessionLimitClockTime() {
        let reset = date("You've hit your session limit · resets 3:45pm")
        XCTAssertEqual(reset, referenceNow.addingTimeInterval(5 * 3600 + 45 * 60))
    }

    func testClockTimeEarlierTodayMeansTomorrow() {
        let reset = date("You've hit your session limit · resets 9am")
        XCTAssertEqual(reset, referenceNow.addingTimeInterval(23 * 3600))
    }

    func testWeeklyLimitWithWeekday() {
        // Wednesday 10:00 → next Monday 00:00 is 4 days 14 hours away.
        let reset = date("You've hit your weekly limit · resets Mon 12:00am")
        XCTAssertEqual(reset, referenceNow.addingTimeInterval(4 * 86400 + 14 * 3600))
    }

    func testNamedTimeZone() {
        // 3pm in New York (EST, UTC-5 in early March) is 20:00 UTC.
        let reset = date("Claude usage limit reached. Your limit will reset at 3pm (America/New_York).")
        XCTAssertEqual(reset, referenceNow.addingTimeInterval(10 * 3600))
    }

    func testEpochFormat() {
        let reset = date("Claude AI usage limit reached|1772640000")
        XCTAssertEqual(reset, Date(timeIntervalSince1970: 1_772_640_000))
    }

    func testRelativeFormat() {
        let reset = date("Usage limit reached, resets in 2 hours 30 minutes")
        XCTAssertEqual(reset, referenceNow.addingTimeInterval(2.5 * 3600))
    }

    func testBareNumberIsNotAClockTime() {
        XCTAssertNil(date("limit resets 5 hours from now"))
    }

    func testBannerDetectionIgnoresRepliesAboutRateLimiting() {
        XCTAssertTrue(LimitParser.isLimitBanner("You’ve hit your session limit · resets 3:45pm"))
        XCTAssertTrue(LimitParser.isLimitBanner("Claude AI usage limit reached|1772640000"))
        XCTAssertFalse(LimitParser.isLimitBanner("Added rate limiting to /api/upload. Usage limit is 20 per minute."))
    }
}

final class ClaudeOutputParserTests: XCTestCase {
    private func parse(_ output: ProcessOutput) -> RunOutcome {
        ClaudeOutputParser.parse(output, now: referenceNow, timeZone: utc)
    }

    func testSuccess() {
        XCTAssertEqual(
            parse(success("Done. 3 files changed.", session: "abc")),
            .success(result: "Done. 3 files changed.", sessionId: "abc", durationMs: 1200, costUSD: 0.02)
        )
    }

    func testReplyAboutRateLimitsIsStillASuccess() {
        let outcome = parse(success("Added a rate limit of 20 requests per minute; the usage limit test passes."))
        guard case .success = outcome else { return XCTFail("Expected success, got \(outcome)") }
    }

    func testErrorWithLimitText() {
        XCTAssertEqual(
            parse(limited("You've hit your session limit · resets 3:45pm", session: "abc")),
            .limited(
                resetsAt: referenceNow.addingTimeInterval(5 * 3600 + 45 * 60),
                message: "You've hit your session limit · resets 3:45pm",
                sessionId: "abc"
            )
        )
    }

    func testLimitBannerReturnedAsSuccess() {
        let outcome = parse(success("Claude AI usage limit reached|1772640000"))
        guard case let .limited(resetsAt, _, _) = outcome else { return XCTFail("Expected limit, got \(outcome)") }
        XCTAssertEqual(resetsAt, Date(timeIntervalSince1970: 1_772_640_000))
    }

    func test429WithoutResetTimeWaitsTheFallback() {
        let output = ProcessOutput(
            exitCode: 1,
            stdout: resultJSON("API Error: 429 Too Many Requests", isError: true, apiStatus: 429),
            stderr: ""
        )
        guard case let .limited(resetsAt, _, _) = parse(output) else { return XCTFail() }
        XCTAssertEqual(resetsAt, referenceNow.addingTimeInterval(LimitParser.fallbackWait))
    }

    func testNotSignedIn() {
        let output = ProcessOutput(exitCode: 1, stdout: "", stderr: "Invalid API key · Please run /login")
        guard case let .failed(_, _, kind) = parse(output) else { return XCTFail() }
        XCTAssertEqual(kind, .notSignedIn)
    }

    func testMaxTurnsIsAGeneralFailure() {
        let output = ProcessOutput(exitCode: 1, stdout: resultJSON("", isError: true, subtype: "error_max_turns"), stderr: "")
        guard case let .failed(message, sessionId, kind) = parse(output) else { return XCTFail() }
        XCTAssertEqual(kind, .general)
        XCTAssertEqual(sessionId, "s1")
        XCTAssertTrue(message.contains("maximum number of turns"))
    }

    func testPlainTextSuccess() {
        let output = ProcessOutput(exitCode: 0, stdout: "All done\n", stderr: "")
        XCTAssertEqual(parse(output), .success(result: "All done", sessionId: nil, durationMs: nil, costUSD: nil))
    }

    func testPlainTextFailure() {
        let output = ProcessOutput(exitCode: 2, stdout: "", stderr: "error: unknown option '--bogus'")
        XCTAssertEqual(parse(output), .failed(message: "error: unknown option '--bogus'", sessionId: nil, kind: .general))
    }

    func testResultLineAfterOtherOutput() {
        let output = ProcessOutput(exitCode: 0, stdout: "warning: something\n" + resultJSON("Hi", session: "z"), stderr: "")
        XCTAssertEqual(parse(output), .success(result: "Hi", sessionId: "z", durationMs: 1200, costUSD: 0.02))
    }
}

final class ClaudeCommandTests: XCTestCase {
    func testArguments() {
        XCTAssertEqual(
            ClaudeCommand.arguments(prompt: "Fix the tests", resumeSessionId: "abc", autoMode: true, model: "opus"),
            ["--output-format", "json", "--resume", "abc", "--permission-mode", "auto", "--model", "opus", "-p", "Fix the tests"]
        )
        XCTAssertEqual(
            ClaudeCommand.arguments(prompt: "Hi", resumeSessionId: nil, autoMode: false, model: " "),
            ["--output-format", "json", "-p", "Hi"]
        )
    }

    func testPromptStartingWithDash() {
        let args = ClaudeCommand.arguments(prompt: "- list the TODOs", resumeSessionId: nil, autoMode: false, model: "")
        XCTAssertEqual(Array(args.suffix(3)), ["-p", "--", "- list the TODOs"])
    }

    func testEnvironmentDropsAPIKeyAndMergesPath() {
        let env = ClaudeCommand.environment(
            base: ["HOME": "/Users/me", "PATH": "/usr/bin:/bin", "ANTHROPIC_API_KEY": "sk-test", "LANG": "en_US.UTF-8"],
            loginShellPath: "/opt/homebrew/bin:/usr/bin"
        )
        XCTAssertNil(env["ANTHROPIC_API_KEY"])
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
        let path = env["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(Array(path.prefix(3)), ["/opt/homebrew/bin", "/usr/bin", "/bin"])
        XCTAssertTrue(path.contains("/Users/me/.local/bin"))
        XCTAssertEqual(path.count, Set(path).count, "PATH entries are de-duplicated")
    }

    func testLocator() {
        let exists: Set<String> = ["/opt/homebrew/bin/claude", "/custom/bin/claude", "/Users/me/.local/bin/claude"]
        let check: (String) -> Bool = { exists.contains($0) }
        XCTAssertEqual(
            ClaudeLocator.locate(override: "", home: "/Users/me", path: nil, isExecutable: check)?.path,
            "/Users/me/.local/bin/claude"
        )
        XCTAssertEqual(
            ClaudeLocator.locate(override: "/custom/bin/claude", home: "/Users/me", path: nil, isExecutable: check)?.path,
            "/custom/bin/claude"
        )
        XCTAssertNil(ClaudeLocator.locate(override: "/missing/claude", home: "/Users/me", path: nil, isExecutable: check))
        XCTAssertEqual(
            ClaudeLocator.locate(override: "", home: "/nobody", path: "/custom/bin", isExecutable: { $0 == "/custom/bin/claude" })?.path,
            "/custom/bin/claude"
        )
    }
}

final class PromptBulkImportTests: XCTestCase {
    func testBlankLinesSeparatePrompts() {
        let prompts = PromptBulkImport.prompts(from: "First prompt\n\nSecond prompt\nwith two lines\n  \nThird")
        XCTAssertEqual(prompts, ["First prompt", "Second prompt\nwith two lines", "Third"])
    }

    func testEachLineWithoutBlankLines() {
        XCTAssertEqual(PromptBulkImport.prompts(from: "A\r\nB\nC"), ["A", "B", "C"])
    }

    func testSinglePromptAndEmpty() {
        XCTAssertEqual(PromptBulkImport.prompts(from: "  just one  "), ["just one"])
        XCTAssertEqual(PromptBulkImport.prompts(from: " \n "), [])
    }
}

final class DurationFormatTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(DurationFormat.short(45), "45s")
        XCTAssertEqual(DurationFormat.short(14 * 60), "14m")
        XCTAssertEqual(DurationFormat.short(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(DurationFormat.short(3600), "1h")
    }

    func testMenuCountdown() {
        XCTAssertEqual(DurationFormat.menuCountdown(2 * 3600 + 14 * 60), "2:14")
        XCTAssertEqual(DurationFormat.menuCountdown(10), "1m")
    }
}
