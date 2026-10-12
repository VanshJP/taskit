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
