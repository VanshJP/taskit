import Foundation
import Observation

public enum RelayEvent: Equatable, Sendable {
    case promptStarted(QueueItem)
    case promptFinished(QueueItem)
    case promptFailed(QueueItem)
    case limitHit(LimitState)
    case limitCleared
    case queueFinished(done: Int, failed: Int)
    /// True while Taskit has work in flight (a prompt running or a limit being waited out).
    case activityChanged(Bool)
}

/// Sends queued prompts to Claude Code one at a time and waits out usage limits.
@MainActor
@Observable
public final class RelayEngine {
    public private(set) var items: [QueueItem] = []
    public private(set) var runState: RunState = .stopped
    public private(set) var limit: LimitState?
    public private(set) var threadSessionId: String?
    /// Why the queue stopped on its own (missing folder, not signed in, …).
    public private(set) var notice: String?
    public private(set) var settings: RelaySettings

    /// App hook for notifications, keep-awake and the like.
    @ObservationIgnored public var onEvent: ((RelayEvent) -> Void)?

    @ObservationIgnored private let store: QueueStoring
    @ObservationIgnored private let runner: ClaudeRunning
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async throws -> Void
    @ObservationIgnored private let environment: () -> [String: String]
    @ObservationIgnored private let locateClaude: (RelaySettings, [String: String]) -> URL?

    @ObservationIgnored private(set) var runTask: Task<Void, Never>?
    @ObservationIgnored private(set) var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isShuttingDown = false

    /// Extra wait after the advertised reset time before retrying.
    public nonisolated static let resetGrace: TimeInterval = 60
    /// Pause after this many failures in a row instead of burning through the queue.
    public nonisolated static let maxConsecutiveFailures = 3

    public nonisolated static let continuousSleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        // ContinuousClock keeps counting while the Mac sleeps.
        try await Task.sleep(for: .seconds(max(0, seconds)))
    }

    public nonisolated static func defaultLocate(_ settings: RelaySettings, _ env: [String: String]) -> URL? {
        ClaudeLocator.locate(override: settings.claudePath, path: env["PATH"])
    }

    public init(
        store: QueueStoring,
        runner: ClaudeRunning = ProcessClaudeRunner(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = RelayEngine.continuousSleep,
        environment: @escaping () -> [String: String] = {
            ClaudeCommand.environment(base: ProcessInfo.processInfo.environment, loginShellPath: nil)
        },
        locateClaude: @escaping (RelaySettings, [String: String]) -> URL? = RelayEngine.defaultLocate
    ) {
        self.store = store
        self.runner = runner
        self.now = now
        self.sleep = sleep
        self.environment = environment
        self.locateClaude = locateClaude

        settings = store.loadSettings()
        let snapshot = store.loadSnapshot()
        // A prompt that was running when Taskit quit never reported back: run it again.
        items = snapshot.items.map { item in
            guard item.status == .running else { return item }
            var copy = item
            copy.status = .queued
            copy.startedAt = nil
            return copy
        }
        runState = snapshot.runState
        limit = snapshot.limit
        threadSessionId = snapshot.threadSessionId
        normalizeRunState()
    }

    /// Call once the app has wired `onEvent`. Resumes a queue that was running at quit.
    public func activate() {
        if runState == .running {
            pump()
        }
        updateActivity()
    }

    // MARK: - Derived state

    public var runningItem: QueueItem? { items.first { $0.status == .running } }
    public var pendingCount: Int { items.filter(\.isPending).count }
    public var doneCount: Int { items.filter { $0.status == .done }.count }
    public var failedCount: Int { items.filter { $0.status == .failed }.count }
    public var hasPending: Bool { items.contains(where: \.isPending) }
    public var hasFinished: Bool { items.contains(where: \.isFinished) }

    /// A prompt is running, or a usage limit is being waited out.
    public var isActive: Bool {
        runState == .running && (runTask != nil || limit != nil)
    }

    public var phase: Phase {
        if items.isEmpty { return .empty }
        switch runState {
        case .paused:
            return .paused
        case .running:
            if runningItem == nil, limit != nil { return .waiting }
            return .running
        case .stopped:
            return hasPending ? .idle : .done
        }
    }

    // MARK: - Queue editing

    @discardableResult
    public func add(_ raw: String) -> Int {
        let prompts = PromptBulkImport.prompts(from: raw)
        guard !prompts.isEmpty else { return 0 }
        let created = now()
        items += prompts.map { QueueItem(prompt: $0, createdAt: created) }
        save()
        if runState == .running { pump() }
        return prompts.count
    }

    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].status != .running else { return }
        items.remove(at: index)
        normalizeRunState()
        save()
        if runState == .running { pump() }
        updateActivity()
    }

    /// Swaps a pending item with the pending item before it.
    public func moveUp(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isPending,
              let previous = items[..<index].lastIndex(where: \.isPending) else { return }
        items.swapAt(index, previous)
        save()
    }

    /// Makes a pending item the next one to run.
    public func moveToTop(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isPending,
              let first = items.firstIndex(where: \.isPending), first < index else { return }
        let item = items.remove(at: index)
        items.insert(item, at: first)
        save()
    }

    /// Re-queues a finished prompt at the end of the queue.
    public func runAgain(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isFinished else { return }
        let original = items.remove(at: index)
        var copy = QueueItem(id: original.id, prompt: original.prompt, createdAt: original.createdAt)
        copy.status = .queued
        items.append(copy)
        save()
        if runState == .running { pump() }
    }

    public func clearFinished() {
        items.removeAll(where: \.isFinished)
        normalizeRunState()
        save()
    }

    // MARK: - Running

    public func start() {
        guard hasPending || runTask != nil else { return }
        notice = nil
        consecutiveFailures = 0
        runState = .running
        save()
        pump()
    }

    /// The current prompt finishes; nothing new starts until `start()`.
    public func pause() {
        guard runState == .running else { return }
        runState = .paused
        cancelWake()
        normalizeRunState()
        save()
        updateActivity()
    }

    /// Stops the running prompt now and pauses the queue. The prompt goes back to the queue.
    public func stopCurrent() {
        guard let task = runTask else { return }
        runState = .paused
        cancelWake()
        save()
        task.cancel()
    }

    /// Skips the rest of a usage-limit wait.
    public func tryNow() {
        limit = nil
        cancelWake()
        notice = nil
        if hasPending || runTask != nil { runState = .running }
        save()
        pump()
    }

    /// Call after the Mac wakes: a reset may have passed while it slept.
    public func systemDidWake() {
        guard let limit else { return }
        if now() >= limit.resetsAt {
            limitWindowElapsed()
        } else if runState == .running {
            scheduleWake()
        }
    }

    /// Call when the app quits: stops the child process but keeps the queue as it was,
    /// so the interrupted prompt runs again next launch.
    public func shutdown() {
        isShuttingDown = true
        cancelWake()
        for index in items.indices where items[index].status == .running {
            items[index].status = .queued
            items[index].startedAt = nil
        }
        save()
        runTask?.cancel()
    }

    public func updateSettings(_ mutate: (inout RelaySettings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }
        let modeChanged = next.conversationMode != settings.conversationMode
            || next.projectURL != settings.projectURL
        settings = next
        if modeChanged {
            // A thread belongs to one folder and one mode.
            threadSessionId = nil
            save()
        }
        store.saveSettings(settings)
    }

    // MARK: - Engine

    private func pump() {
        guard runState == .running, runTask == nil, !isShuttingDown else {
            updateActivity()
            return
        }

        guard let index = items.firstIndex(where: \.isPending) else {
            runState = .stopped
            cancelWake()
            save()
            if doneCount + failedCount > 0 {
                onEvent?(.queueFinished(done: doneCount, failed: failedCount))
            }
            updateActivity()
            return
        }

        if let limit {
            if now() < limit.resetsAt {
                if wakeTask == nil { scheduleWake() }
                updateActivity()
                return
            }
            self.limit = nil
        }

        guard let workingDirectory = settings.projectURL else {
            pauseWithNotice("Choose a project folder, then resume.")
            return
        }
        let env = environment()
        guard let executable = locateClaude(settings, env) else {
            pauseWithNotice("Claude Code wasn’t found. Install it, or set its location in Settings.")
            return
        }

        let resume: String?
        switch settings.conversationMode {
        case .oneThread: resume = threadSessionId
        case .fresh: resume = items[index].status == .waiting ? items[index].sessionId : nil
        }

        items[index].status = .running
        items[index].startedAt = now()
        items[index].finishedAt = nil
        items[index].error = nil
        items[index].result = nil
        let item = items[index]

        let invocation = ClaudeInvocation(
            executable: executable,
            arguments: ClaudeCommand.arguments(
                prompt: item.prompt,
                resumeSessionId: resume,
                autoMode: settings.autoMode,
                model: settings.model
            ),
            workingDirectory: workingDirectory,
            environment: env
        )

        notice = nil
        save()
        onEvent?(.promptStarted(item))

        let runner = self.runner
        let itemID = item.id
        runTask = Task { [weak self] in
            let output: Result<ProcessOutput, Error>
            do {
                output = .success(try await runner.run(invocation))
            } catch {
                output = .failure(error)
            }
            let cancelled = Task.isCancelled
            self?.finish(itemID: itemID, output: output, cancelled: cancelled)
        }
        updateActivity()
    }

    private func finish(itemID: UUID, output: Result<ProcessOutput, Error>, cancelled: Bool) {
        runTask = nil
        if isShuttingDown { return }

        let outcome: RunOutcome
        if cancelled {
            outcome = .cancelled
        } else {
            switch output {
            case .success(let processOutput):
                outcome = ClaudeOutputParser.parse(processOutput, now: now())
            case .failure(let error):
                outcome = .failed(message: error.localizedDescription, sessionId: nil, kind: .launch)
            }
        }

        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            pump()
            return
        }

        let finishedAt = now()
        switch outcome {
        case let .success(result, sessionId, durationMs, costUSD):
            consecutiveFailures = 0
            items[index].status = .done
            items[index].result = result
            items[index].error = nil
            items[index].sessionId = sessionId ?? items[index].sessionId
            items[index].finishedAt = finishedAt
            items[index].durationMs = durationMs ?? elapsedMs(since: items[index].startedAt, until: finishedAt)
            items[index].costUSD = costUSD
            rememberThread(sessionId)
            onEvent?(.promptFinished(items[index]))

        case let .limited(resetsAt, message, sessionId):
            items[index].status = .waiting
            items[index].error = message
            items[index].startedAt = nil
            if let sessionId { items[index].sessionId = sessionId }
            rememberThread(sessionId)
            let state = LimitState(resetsAt: resetsAt, message: message, hitAt: finishedAt)
            limit = state
            cancelWake()
            onEvent?(.limitHit(state))

        case let .failed(message, sessionId, kind):
            consecutiveFailures += 1
            items[index].status = .failed
            items[index].error = message
            items[index].finishedAt = finishedAt
            items[index].durationMs = elapsedMs(since: items[index].startedAt, until: finishedAt)
            if let sessionId { items[index].sessionId = sessionId }
            rememberThread(sessionId)
            onEvent?(.promptFailed(items[index]))
            if kind != .general {
                pauseWithNotice(message)
                return
            }
            if consecutiveFailures >= Self.maxConsecutiveFailures {
                pauseWithNotice("\(consecutiveFailures) prompts failed in a row, so Taskit paused. Check the errors, then resume.")
                return
            }

        case .cancelled:
            items[index].status = .queued
            items[index].startedAt = nil
        }

        normalizeRunState()
        save()
        pump()
    }

    private func scheduleWake() {
        wakeTask?.cancel()
        guard let limit else {
            wakeTask = nil
            return
        }
        let delay = max(0, limit.resetsAt.timeIntervalSince(now())) + Self.resetGrace
        let sleep = self.sleep
        wakeTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.limitWindowElapsed()
        }
    }

    private func limitWindowElapsed() {
        wakeTask = nil
        guard limit != nil else { return }
        limit = nil
        save()
        onEvent?(.limitCleared)
        pump()
        updateActivity()
    }

    private func cancelWake() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    private func pauseWithNotice(_ message: String) {
        runState = .paused
        notice = message
        cancelWake()
        normalizeRunState(keepNotice: true)
        save()
        updateActivity()
    }

    private func rememberThread(_ sessionId: String?) {
        guard settings.conversationMode == .oneThread, let sessionId, !sessionId.isEmpty else { return }
        threadSessionId = sessionId
    }

    /// A paused queue with nothing left to do is simply stopped.
    private func normalizeRunState(keepNotice: Bool = false) {
        if runState == .paused, runTask == nil, !hasPending, !keepNotice {
            runState = .stopped
        }
    }

    private func updateActivity() {
        let active = isActive
        guard active != lastActivity else { return }
        lastActivity = active
        onEvent?(.activityChanged(active))
    }

    private func elapsedMs(since start: Date?, until end: Date) -> Int? {
        guard let start else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    private func save() {
        store.saveSnapshot(QueueSnapshot(
            items: items,
            runState: runState,
            limit: limit,
            threadSessionId: threadSessionId
        ))
    }

    // MARK: - Testing

    /// Waits until no prompt is running (including any the finished one started).
    func waitForIdle() async {
        while let task = runTask {
            await task.value
        }
    }

    func waitForWake() async {
        if let task = wakeTask { await task.value }
    }
}
