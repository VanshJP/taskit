import XCTest
@testable import TaskitCore

final class LimitDetectorTests: XCTestCase {
    func testDetectsRelativeHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let signal = LimitDetector.detect(
            in: "You've hit your rate limit. Please wait for your limit to reset in 5 hours.",
            now: now
        )
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.resetAt?.timeIntervalSince(now) ?? 0, 5 * 3600, accuracy: 1)
    }

    func testDetectsHoursAndMinutes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let signal = LimitDetector.detect(
            in: "Please wait for your limit to reset in 2 hours 25 minutes.",
            now: now
        )
        XCTAssertNotNil(signal)
        let expected = (2 * 3600) + (25 * 60)
        XCTAssertEqual(signal?.resetAt?.timeIntervalSince(now) ?? 0, TimeInterval(expected), accuracy: 1)
    }

    func testHTTP429Fallback() {
        let now = Date()
        let signal = LimitDetector.detect(statusCode: 429, body: "too many requests", now: now)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.resetAt?.timeIntervalSince(now) ?? 0, SessionClock.defaultWindowSeconds, accuracy: 2)
    }

    func testIgnoresOrdinaryErrors() {
        XCTAssertNil(LimitDetector.detect(in: "Repository not found"))
    }
}

final class SessionClockTests: XCTestCase {
    func testCoolingBecomesReady() {
        var clock = SessionClock()
        clock.markLimitHit(reason: "test", resetAt: Date().addingTimeInterval(-1))
        XCTAssertTrue(clock.tick())
        XCTAssertEqual(clock.phase, .ready)
    }

    func testComposedPromptIncludesOverarchingGoal() {
        var settings = AppSettings.default
        settings.overarchingGoal = "Ship billing"
        settings.prependOverarchingGoal = true
        let goal = Goal(title: "Step 1", prompt: "Add invoice PDF export")
        let text = settings.composedPrompt(for: goal)
        XCTAssertTrue(text.contains("Ship billing"))
        XCTAssertTrue(text.contains("Add invoice PDF export"))
    }
}

final class DurationFormatTests: XCTestCase {
    func testClockFormatting() {
        XCTAssertEqual(DurationFormat.clock(0), "00:00")
        XCTAssertEqual(DurationFormat.clock(65), "01:05")
        XCTAssertEqual(DurationFormat.clock(5 * 3600 + 12 * 60 + 8), "5:12:08")
    }

    func testRemainingNeverNegative() {
        let past = Date().addingTimeInterval(-30)
        XCTAssertEqual(DurationFormat.remaining(until: past), 0)
        XCTAssertEqual(DurationFormat.remaining(until: nil), 0)
    }
}

final class PersistenceEfficiencyTests: XCTestCase {
    func testCompactEncoderDoesNotPrettyPrint() throws {
        let goals = [Goal(title: "A", prompt: "Do A")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taskit-goals-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        Persistence.save(goals, to: url)
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("\n  "), "Persistence should write compact JSON")
        XCTAssertTrue(text.contains("Do A"))
    }
}

final class PromptBulkImportTests: XCTestCase {
    func testSplitsOnBlankLines() {
        let raw = """
        First prompt

        Second prompt
        with two lines

        Third
        """
        let prompts = PromptBulkImport.prompts(from: raw)
        XCTAssertEqual(prompts.count, 3)
        XCTAssertTrue(prompts[1].contains("with two lines"))
    }

    func testFallsBackToSingleLines() {
        let prompts = PromptBulkImport.prompts(from: "A\nB\nC")
        XCTAssertEqual(prompts, ["A", "B", "C"])
    }

    func testSettingsDecodeMissingPauseDefaultsFalse() throws {
        let json = """
        {"overarchingGoal":"Ship it","repositoryURL":"","startingRef":"main","modelId":"","autoCreatePR":true,"dispatchMode":"continueAgent","autoContinueOnFinish":true,"autoResumeOnLimitReset":true,"sessionWindowHours":5,"prependOverarchingGoal":true,"launchAtLogin":true,"notifyOnDispatch":true,"notifyOnComplete":true,"notifyOnLimit":true}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.sessionFlowPaused)
        XCTAssertEqual(settings.overarchingGoal, "Ship it")
    }
}
