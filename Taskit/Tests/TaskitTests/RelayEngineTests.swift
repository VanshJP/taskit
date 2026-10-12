import XCTest
@testable import TaskitCore

@MainActor
final class RelayEngineTests: XCTestCase {
    private var events: [RelayEvent] = []

    private func makeEngine(
        runner: ClaudeRunning,
        store: MemoryQueueStore = MemoryQueueStore(settings: readySettings()),
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) },
        now: @escaping () -> Date = { referenceNow },
        locate: @escaping (RelaySettings, [String: String]) -> URL? = { _, _ in fakeClaude }
    ) -> RelayEngine {
        let engine = RelayEngine(
            store: store,
            runner: runner,
            now: now,
            sleep: sleep,
            environment: { ["PATH": "/usr/bin"] },
            locateClaude: locate
        )
        events = []
        engine.onEvent = { [weak self] in self?.events.append($0) }
        engine.activate()
        return engine
    }

    private func prompts(_ invocations: [ClaudeInvocation]) -> [String] {
        invocations.compactMap(\.arguments.last)
    }

    private func resumeIDs(_ invocations: [ClaudeInvocation]) -> [String?] {
        invocations.map { inv in
            inv.arguments.firstIndex(of: "--resume").map { inv.arguments[$0 + 1] }
        }
    }

    // MARK: - Running the queue

    func testRunsWholeQueueInOrderAndContinuesTheThread() async {
        let runner = ScriptedRunner([success("one", session: "a"), success("two", session: "b"), success("three", session: "c")])
        let engine = makeEngine(runner: runner)
        engine.add("First\nSecond\nThird")
        XCTAssertEqual(engine.phase, .idle)

        engine.start()
        await engine.waitForIdle()

        XCTAssertEqual(prompts(runner.invocations), ["First", "Second", "Third"])
        XCTAssertEqual(resumeIDs(runner.invocations), [nil, "a", "b"])
        XCTAssertEqual(engine.items.map(\.status), [.done, .done, .done])
        XCTAssertEqual(engine.items.map(\.result), ["one", "two", "three"])
        XCTAssertEqual(engine.runState, .stopped)
        XCTAssertEqual(engine.phase, .done)
        XCTAssertEqual(engine.threadSessionId, "c")
        XCTAssertTrue(events.contains(.queueFinished(done: 3, failed: 0)))
        XCTAssertEqual(runner.invocations.first?.workingDirectory.path, "/tmp/taskit-project")
        XCTAssertTrue(runner.invocations.allSatisfy { $0.arguments.contains("--permission-mode") })
    }

    func testFreshModeNeverResumes() async {
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner, store: MemoryQueueStore(settings: readySettings(.fresh)))
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(resumeIDs(runner.invocations), [nil, nil])
    }

    func testStartingTwiceNeverRunsTwoPromptsAtOnce() async {
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner)
        engine.add("A\nB\nC")
        engine.start()
        engine.start()
        engine.pause()
        engine.start()
        XCTAssertEqual(engine.items.filter { $0.status == .running }.count, 1)
        await engine.waitForIdle()
        XCTAssertEqual(prompts(runner.invocations), ["A", "B", "C"])
        XCTAssertEqual(engine.items.map(\.status), [.done, .done, .done])
    }

    func testPromptsAddedWhileRunningAreQueuedBehind() async {
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner)
        engine.add("A")
        engine.start()
        engine.add("B")
        await engine.waitForIdle()
        XCTAssertEqual(prompts(runner.invocations), ["A", "B"])
    }

    func testReplyAboutRateLimitingDoesNotPauseTheQueue() async {
        let runner = ScriptedRunner([success("Added rate limiting. The usage limit is 20/min."), success("ok")])
        let engine = makeEngine(runner: runner)
        engine.add("Add rate limiting\nNext")
        engine.start()
        await engine.waitForIdle()
        XCTAssertNil(engine.limit)
        XCTAssertEqual(engine.items.map(\.status), [.done, .done])
    }

    // MARK: - Pause and stop

    func testPauseLetsCurrentPromptFinish() async {
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner)
        engine.add("A\nB")
        engine.start()
        engine.pause()
        XCTAssertEqual(engine.phase, .paused)
        await engine.waitForIdle()

        XCTAssertEqual(engine.items.map(\.status), [.done, .queued])
        XCTAssertEqual(engine.runState, .paused)

        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.items.map(\.status), [.done, .done])
        XCTAssertEqual(engine.runState, .stopped)
    }

    func testStopCurrentRequeuesThePrompt() async {
        let engine = makeEngine(runner: BlockingRunner())
        engine.add("Long task\nAfter")
        engine.start()
        XCTAssertEqual(engine.runningItem?.prompt, "Long task")

        engine.stopCurrent()
        await engine.waitForIdle()

        XCTAssertEqual(engine.items.map(\.status), [.queued, .queued])
        XCTAssertEqual(engine.runState, .paused)
        XCTAssertNil(engine.runningItem)
    }

    // MARK: - Usage limits

    func testLimitWaitsForResetThenRetriesInTheSameSession() async {
        let sleeper = InstantSleeper()
        let runner = ScriptedRunner([
            success("one", session: "a"),
            limited("You've hit your session limit · resets 11:00am", session: "b"),
            success("two", session: "c")
        ])
        let engine = makeEngine(runner: runner, sleep: sleeper.sleep)
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()
        await engine.waitForWake()
        await engine.waitForIdle()

        XCTAssertEqual(prompts(runner.invocations), ["A", "B", "B"])
        XCTAssertEqual(resumeIDs(runner.invocations), [nil, "a", "b"])
        XCTAssertEqual(sleeper.delays.count, 1)
        XCTAssertEqual(sleeper.delays[0], 3600 + RelayEngine.resetGrace, accuracy: 1)
        XCTAssertEqual(engine.items.map(\.status), [.done, .done])
        XCTAssertTrue(events.contains(.limitCleared))
    }

    func testWaitingStateAndTryNow() async {
        let runner = ScriptedRunner([limited("Claude usage limit reached. Your limit will reset at 3pm (UTC).")])
        let engine = makeEngine(runner: runner)
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()

        XCTAssertEqual(engine.phase, .waiting)
        XCTAssertEqual(engine.limit?.resetsAt, referenceNow.addingTimeInterval(5 * 3600))
        XCTAssertEqual(engine.items.map(\.status), [.waiting, .queued])
        XCTAssertNotNil(engine.wakeTask)
        XCTAssertTrue(events.contains(.activityChanged(true)))

        engine.tryNow()
        XCTAssertNil(engine.limit)
        await engine.waitForIdle()
        XCTAssertEqual(engine.items.map(\.status), [.done, .done])
        XCTAssertTrue(events.contains(.activityChanged(false)))
    }

    func testPausingDuringLimitStopsTheTimer() async {
        let runner = ScriptedRunner([limited("You've hit your session limit · resets 3:45pm")])
        let engine = makeEngine(runner: runner)
        engine.add("A")
        engine.start()
        await engine.waitForIdle()
        engine.pause()
        XCTAssertNil(engine.wakeTask)
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertNotNil(engine.limit, "The reset time is kept for when the queue resumes")
    }

    func testRemovingEverythingDuringALimitStopsTheQueue() async {
        let runner = ScriptedRunner([limited("You've hit your session limit · resets 3:45pm")])
        let engine = makeEngine(runner: runner)
        engine.add("A")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.phase, .waiting)

        engine.remove(engine.items[0].id)
        XCTAssertEqual(engine.phase, .empty)
        XCTAssertEqual(engine.runState, .stopped)
        XCTAssertNil(engine.wakeTask)
        XCTAssertFalse(engine.isActive)
    }

    func testWakeAfterResetResumesImmediately() async {
        var clock = referenceNow
        let runner = ScriptedRunner([limited("You've hit your session limit · resets 10:30am")])
        let engine = makeEngine(runner: runner, now: { clock })
        engine.add("A")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.phase, .waiting)

        clock = referenceNow.addingTimeInterval(3600)
        engine.systemDidWake()
        await engine.waitForIdle()
        XCTAssertEqual(engine.items.map(\.status), [.done])
    }

    // MARK: - Failures

    func testFailureMovesOnToTheNextPrompt() async {
        let runner = ScriptedRunner([failure("Something broke"), success("ok")])
        let engine = makeEngine(runner: runner)
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.items.map(\.status), [.failed, .done])
        XCTAssertEqual(engine.items[0].error, "Something broke")
        XCTAssertTrue(events.contains(.queueFinished(done: 1, failed: 1)))
    }

    func testRepeatedFailuresPause() async {
        let runner = ScriptedRunner([failure("x"), failure("y"), failure("z")])
        let engine = makeEngine(runner: runner)
        engine.add("A\nB\nC\nD")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.items.map(\.status), [.failed, .failed, .failed, .queued])
        XCTAssertEqual(engine.runState, .paused)
        XCTAssertNotNil(engine.notice)
    }

    func testNotSignedInPausesWithNotice() async {
        let runner = ScriptedRunner([ProcessOutput(exitCode: 1, stdout: "", stderr: "Not logged in · Please run /login")])
        let engine = makeEngine(runner: runner)
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertEqual(engine.items.map(\.status), [.failed, .queued])
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertTrue(engine.notice?.contains("signed in") ?? false)
    }

    func testMissingFolderOrClaudePausesWithoutRunning() {
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner, store: MemoryQueueStore(settings: .default))
        engine.add("A")
        engine.start()
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertNotNil(engine.notice)

        let other = makeEngine(runner: runner, locate: { _, _ in nil })
        other.add("A")
        other.start()
        XCTAssertTrue(other.notice?.contains("wasn’t found") ?? false)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    // MARK: - Editing

    func testEditingTheQueue() {
        let engine = makeEngine(runner: ScriptedRunner())
        engine.add("A\nB\nC")
        let ids = engine.items.map(\.id)

        engine.moveUp(ids[2])
        XCTAssertEqual(engine.items.map(\.prompt), ["A", "C", "B"])
        engine.moveToTop(ids[1])
        XCTAssertEqual(engine.items.map(\.prompt), ["B", "A", "C"])
        engine.remove(ids[0])
        XCTAssertEqual(engine.items.map(\.prompt), ["B", "C"])
    }

    func testRunningPromptCannotBeRemoved() {
        let engine = makeEngine(runner: BlockingRunner())
        engine.add("A")
        engine.start()
        engine.remove(engine.items[0].id)
        XCTAssertEqual(engine.items.count, 1)
        engine.stopCurrent()
    }

    func testRunAgainAndClearFinished() async {
        let runner = ScriptedRunner([failure("x"), success("ok")])
        let engine = makeEngine(runner: runner)
        engine.add("A\nB")
        engine.start()
        await engine.waitForIdle()

        engine.runAgain(engine.items[0].id)
        XCTAssertEqual(engine.items.map(\.prompt), ["B", "A"])
        XCTAssertEqual(engine.items[1].status, .queued)
        XCTAssertNil(engine.items[1].error)

        engine.clearFinished()
        XCTAssertEqual(engine.items.map(\.prompt), ["A"])
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: - Persistence

    func testInterruptedPromptRunsAgainAfterRelaunch() async {
        var running = QueueItem(prompt: "Interrupted")
        running.status = .running
        let store = MemoryQueueStore(
            snapshot: QueueSnapshot(items: [running, QueueItem(prompt: "Next")], runState: .running),
            settings: readySettings()
        )
        let runner = ScriptedRunner()
        let engine = makeEngine(runner: runner, store: store)
        await engine.waitForIdle()
        XCTAssertEqual(prompts(runner.invocations), ["Interrupted", "Next"])
        XCTAssertEqual(store.snapshot.items.map(\.status), [.done, .done])
        XCTAssertEqual(store.snapshot.runState, .stopped)
    }

    func testChangingFolderStartsANewThread() async {
        let engine = makeEngine(runner: ScriptedRunner([success("ok", session: "a")]))
        engine.add("A")
        engine.start()
        await engine.waitForIdle()
        XCTAssertEqual(engine.threadSessionId, "a")
        engine.updateSettings { $0.projectPath = "/tmp/other" }
        XCTAssertNil(engine.threadSessionId)
    }

    func testFileStoreRoundTripAndCorruptBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("taskit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileQueueStore(directory: dir)

        var item = QueueItem(prompt: "Hello", createdAt: referenceNow)
        item.status = .done
        item.result = "Hi"
        let snapshot = QueueSnapshot(
            items: [item],
            runState: .paused,
            limit: LimitState(resetsAt: referenceNow, message: "limit"),
            threadSessionId: "t"
        )
        store.saveSnapshot(snapshot)
        store.saveSettings(readySettings())
        XCTAssertEqual(store.loadSnapshot(), snapshot)
        XCTAssertEqual(store.loadSettings(), readySettings())

        try Data("not json".utf8).write(to: store.queueURL)
        XCTAssertEqual(store.loadSnapshot(), QueueSnapshot())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.queueURL.appendingPathExtension("corrupt").path))
    }

    func testSettingsDecodeWithMissingKeys() throws {
        let settings = try JSONDecoder().decode(RelaySettings.self, from: Data(#"{"projectPath":"~/code/app"}"#.utf8))
        XCTAssertEqual(settings.projectPath, "~/code/app")
        XCTAssertEqual(settings.conversationMode, .oneThread)
        XCTAssertTrue(settings.autoMode)
        XCTAssertEqual(settings.projectName, "app")
    }
}

final class ProcessClaudeRunnerTests: XCTestCase {
    private func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func invocation(_ executable: URL, _ args: [String] = []) -> ClaudeInvocation {
        ClaudeInvocation(
            executable: executable,
            arguments: args,
            workingDirectory: FileManager.default.temporaryDirectory,
            environment: ["PATH": "/usr/bin:/bin", "TASKIT_TEST": "yes"]
        )
    }

    func testCapturesOutputArgumentsAndEnvironment() async throws {
        let exe = try script(#"echo "args:$*"; echo "env:$TASKIT_TEST"; echo "oops" >&2; exit 3"#)
        defer { try? FileManager.default.removeItem(at: exe) }
        let output = try await ProcessClaudeRunner().run(invocation(exe, ["-p", "hello world"]))
        XCTAssertEqual(output.exitCode, 3)
        XCTAssertEqual(output.stdout, "args:-p hello world\nenv:yes\n")
        XCTAssertEqual(output.stderr, "oops\n")
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        let exe = try script("head -c 300000 /dev/zero | tr '\\\\0' 'a'; head -c 300000 /dev/zero | tr '\\\\0' 'b' >&2")
        defer { try? FileManager.default.removeItem(at: exe) }
        let output = try await ProcessClaudeRunner().run(invocation(exe))
        XCTAssertEqual(output.stdout.count, 300_000)
        XCTAssertEqual(output.stderr.count, 300_000)
    }

    func testCancellationTerminatesTheProcess() async throws {
        let exe = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: exe) }
        let started = Date()
        let task = Task { try await ProcessClaudeRunner().run(invocation(exe)) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let output = try await task.value
        XCTAssertNotEqual(output.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    #if os(macOS)
    // Linux Foundation only reports termination once every inheritor of the child's
    // fds exits, so this only holds on macOS (where Taskit runs).
    func testBackgroundChildHoldingThePipeDoesNotHang() async throws {
        // A tool Claude starts can outlive it and keep stdout open.
        let exe = try script("sleep 30 &\necho done")
        defer { try? FileManager.default.removeItem(at: exe) }
        let started = Date()
        let output = try await ProcessClaudeRunner().run(invocation(exe))
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, "done\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
    #endif

    func testMissingExecutableThrows() async {
        do {
            _ = try await ProcessClaudeRunner().run(invocation(URL(fileURLWithPath: "/nonexistent/claude")))
            XCTFail("Expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Couldn’t start Claude Code"))
        }
    }
}
