import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class RelayEngine {
    public private(set) var goals: [Goal] = []
    /// Pre-sorted mirror of `goals` — avoids O(n log n) sorts on every SwiftUI body.
    public private(set) var orderedGoals: [Goal] = []
    public private(set) var completedCount = 0
    public private(set) var queuedCount = 0

    public var settings: AppSettings = .default
    public var session: SessionClock = .init()
    /// Small ring for diagnostics — not rendered in the hot UI path.
    public private(set) var events: [DispatchEvent] = []
    public var isBusy = false
    public var statusMessage = "Queue a few prompts for the day."
    public var apiKeyPresent = false

    private var pollTask: Task<Void, Never>?
    private var coolingWakeTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var settingsDebounceTask: Task<Void, Never>?
    private var dirty: Set<PersistKey> = []
    private var apiKey: String = ""
    private var wakeObserver: NSObjectProtocol?
    private var pollBackoffNanoseconds: UInt64 = 2_000_000_000
    private var cachedClient: CursorAPIClient?

    private static let maxEvents = 24
    private static let persistDebounceNanoseconds: UInt64 = 250_000_000
    private static let settingsDebounceNanoseconds: UInt64 = 400_000_000
    private static let pollFloorNanoseconds: UInt64 = 2_000_000_000
    private static let pollCeilNanoseconds: UInt64 = 15_000_000_000

    public var queuedGoals: [Goal] {
        orderedGoals.filter { $0.status == .queued || $0.status == .waitingOnLimit }
    }

    public var activeGoal: Goal? {
        orderedGoals.first { $0.status == .running || $0.status == .dispatching }
    }

    public var nextGoal: Goal? {
        orderedGoals.first { $0.status == .queued || $0.status == .waitingOnLimit }
    }

    public var isPaused: Bool { settings.sessionFlowPaused }

    public var readinessIssues: [String] {
        var issues: [String] = []
        if !apiKeyPresent { issues.append("Add a Cursor API key") }
        if settings.overarchingGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Set today’s overarching goal")
        }
        if queuedCount == 0 { issues.append("Queue at least one prompt") }
        return issues
    }

    public init() {
        reload()
        installWakeObserver()
        armCoolingWakeIfNeeded()
        resumePollingIfNeeded()
    }

    // MARK: - Labels (pure — no stored ticking state)

    public func menuBarLabel(at now: Date = .now) -> String {
        switch session.phase {
        case .cooling:
            return DurationFormat.clock(DurationFormat.remaining(until: session.coolingUntil, now: now))
        case .ready:
            return "Ready"
        case .active:
            return String(activeGoal?.displayTitle.prefix(18) ?? "Active")
        case .idle:
            return queuedCount == 0 ? "Taskit" : "\(queuedCount) left"
        }
    }

    public func remainingCoolingLabel(at now: Date = .now) -> String {
        DurationFormat.clock(DurationFormat.remaining(until: session.coolingUntil, now: now))
    }

    public func coolingProgress(at now: Date = .now) -> Double {
        guard session.phase == .cooling, session.windowSeconds > 0 else {
            return session.phase == .ready ? 1 : 0
        }
        let remaining = DurationFormat.remaining(until: session.coolingUntil, now: now)
        return min(1, max(0, 1 - (remaining / session.windowSeconds)))
    }

    // MARK: - Lifecycle

    public func reload() {
        goals = Persistence.load([Goal].self, from: Persistence.goalsURL, fallback: [])
        settings = Persistence.load(AppSettings.self, from: Persistence.settingsURL, fallback: .default)
        session = Persistence.load(SessionClock.self, from: Persistence.sessionURL, fallback: .init())
        events = Persistence.load([DispatchEvent].self, from: Persistence.eventsURL, fallback: [])
        if events.count > Self.maxEvents {
            events = Array(events.prefix(Self.maxEvents))
        }
        session.windowSeconds = settings.sessionWindowSeconds
        apiKey = KeychainStore.loadAPIKey() ?? ""
        apiKeyPresent = !apiKey.isEmpty
        rebuildGoalDerivedState()
        invalidateClient()
        if session.tick() {
            statusMessage = "Limit window cleared. Ready to continue."
            markDirty(.session)
            flushPersistenceNow()
        }
    }

    public func persist() {
        markDirty(.goals, .settings, .session, .events)
        flushPersistenceNow()
    }

    public func updateAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.deleteAPIKey()
            apiKey = ""
            apiKeyPresent = false
        } else {
            try? KeychainStore.saveAPIKey(trimmed)
            apiKey = trimmed
            apiKeyPresent = true
        }
        invalidateClient()
    }

    public func addGoal(title: String, prompt: String) {
        let nextIndex = (goals.map(\.sortIndex).max() ?? -1) + 1
        let goal = Goal(title: title, prompt: prompt, sortIndex: nextIndex)
        goals.append(goal)
        rebuildGoalDerivedState()
        statusMessage = "Added “\(goal.displayTitle)”."
        markDirty(.goals)
        schedulePersist()
    }

    @discardableResult
    public func addGoalsFromPaste(_ raw: String) -> Int {
        let prompts = PromptBulkImport.prompts(from: raw)
        guard !prompts.isEmpty else { return 0 }
        var nextIndex = (goals.map(\.sortIndex).max() ?? -1) + 1
        for prompt in prompts {
            let goal = Goal(
                title: PromptBulkImport.titleHint(for: prompt),
                prompt: prompt,
                sortIndex: nextIndex
            )
            goals.append(goal)
            nextIndex += 1
        }
        rebuildGoalDerivedState()
        statusMessage = prompts.count == 1
            ? "Added “\(PromptBulkImport.titleHint(for: prompts[0]))”."
            : "Added \(prompts.count) prompts from paste."
        markDirty(.goals)
        schedulePersist()
        return prompts.count
    }

    public func updateGoal(_ goal: Goal, title: String, prompt: String) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].title = title
        goals[idx].prompt = prompt
        rebuildGoalDerivedState()
        statusMessage = "Updated “\(goals[idx].displayTitle)”."
        markDirty(.goals)
        schedulePersist()
    }

    public func requeueGoal(_ goal: Goal) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].status = .queued
        goals[idx].lastError = nil
        goals[idx].completedAt = nil
        goals[idx].startedAt = nil
        rebuildGoalDerivedState()
        statusMessage = "Requeued “\(goals[idx].displayTitle)”."
        markDirty(.goals)
        schedulePersist()
    }

    public func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        reindex()
        rebuildGoalDerivedState()
        markDirty(.goals)
        schedulePersist()
    }

    public func setPaused(_ paused: Bool) {
        settings.sessionFlowPaused = paused
        statusMessage = paused
            ? "Relay paused — auto-continue is holding."
            : "Relay armed — auto-continue is on."
        markDirty(.settings)
        schedulePersist()
        if !paused, settings.autoResumeOnLimitReset || settings.autoContinueOnFinish {
            Task { await startRelay() }
        }
    }

    public func copyComposedPrompt(for goal: Goal? = nil) {
        let target = goal ?? nextGoal
        guard let target else {
            statusMessage = "Nothing to copy — queue a prompt first."
            return
        }
        let text = settings.composedPrompt(for: target)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Copied “\(target.displayTitle)” to clipboard."
    }

    public func verifyAPIConnection() async {
        guard apiKeyPresent else {
            statusMessage = "Add a Cursor API key in Settings first."
            return
        }
        statusMessage = "Checking Cursor API…"
        do {
            try await client().verifyConnection()
            statusMessage = "Cursor API key looks good."
        } catch {
            statusMessage = "API check failed: \(error.localizedDescription)"
        }
    }

    public func moveGoals(from source: IndexSet, to destination: Int) {
        var ordered = orderedGoals
        ordered.move(fromOffsets: source, toOffset: destination)
        for (idx, item) in ordered.enumerated() {
            if let i = goals.firstIndex(where: { $0.id == item.id }) {
                goals[i].sortIndex = idx
            }
        }
        rebuildGoalDerivedState()
        markDirty(.goals)
        schedulePersist()
    }

    /// Immediate settings mutation (toggles, pickers).
    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        session.windowSeconds = settings.sessionWindowSeconds
        LaunchAtLogin.setEnabled(settings.launchAtLogin)
        markDirty(.settings, .session)
        schedulePersist()
    }

    /// Debounced settings mutation for free-typing fields — keeps typing smooth and avoids disk thrash.
    public func updateSettingsDebounced(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        session.windowSeconds = settings.sessionWindowSeconds
        markDirty(.settings, .session)
        settingsDebounceTask?.cancel()
        settingsDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settingsDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.schedulePersist()
        }
    }

    public func startRelay() async {
        guard !isBusy else { return }
        if settings.sessionFlowPaused {
            settings.sessionFlowPaused = false
            markDirty(.settings)
        }
        if session.phase == .cooling, !session.isReadyToDispatch {
            statusMessage = "Still cooling — \(remainingCoolingLabel()) left."
            return
        }
        if session.phase == .ready || session.phase == .cooling {
            session.markActive()
            coolingWakeTask?.cancel()
            markDirty(.session)
        }
        await dispatchNextIfPossible()
    }

    public func markLimitHit(customHours: Double? = nil) {
        let hours = customHours ?? settings.sessionWindowHours
        session.windowSeconds = max(15 * 60, hours * 3600)
        session.markLimitHit(reason: "Marked manually — waiting for the next window.")
        if let active = activeGoal, let idx = goals.firstIndex(where: { $0.id == active.id }) {
            goals[idx].status = .waitingOnLimit
            rebuildGoalDerivedState()
            markDirty(.goals)
        }
        if let next = queuedGoals.first {
            NotificationService.shared.scheduleLimitResume(
                at: session.coolingUntil ?? Date().addingTimeInterval(session.windowSeconds),
                goalTitle: next.displayTitle
            )
        }
        appendEvent(.init(kind: .limitHit, message: "Session marked as limited. Auto-resume armed."))
        statusMessage = "Cooling for \(DurationFormat.clock(session.windowSeconds)). Next prompt will fire automatically."
        if settings.notifyOnLimit {
            NotificationService.shared.post(
                title: "Limit window started",
                body: "Taskit will re-prompt in \(DurationFormat.clock(session.windowSeconds))."
            )
        }
        markDirty(.session, .events)
        flushPersistenceNow()
        armCoolingWakeIfNeeded()
    }

    public func skipGoal(_ goal: Goal) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].status = .skipped
        goals[idx].completedAt = .now
        rebuildGoalDerivedState()
        appendEvent(.init(kind: .skipped, message: "Skipped \(goal.displayTitle)", goalId: goal.id))
        markDirty(.goals, .events)
        schedulePersist()
    }

    public func resetDay() {
        pollTask?.cancel()
        coolingWakeTask?.cancel()
        goals = []
        rebuildGoalDerivedState()
        session.markIdle()
        events = []
        settings.activeAgentId = nil
        statusMessage = "Fresh day. Queue your prompts."
        markDirty(.goals, .settings, .session, .events)
        flushPersistenceNow()
    }

    public func openActiveAgent() {
        guard let urlString = activeGoal?.agentURL ?? goals.last(where: { $0.agentURL != nil })?.agentURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Scheduling

    private func installWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePossibleCoolingElapsed()
            }
        }
    }

    private func armCoolingWakeIfNeeded() {
        coolingWakeTask?.cancel()
        guard session.phase == .cooling, let until = session.coolingUntil else { return }

        let delay = max(0, until.timeIntervalSinceNow)
        coolingWakeTask = Task { [weak self] in
            let nanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.handlePossibleCoolingElapsed()
            }
        }
    }

    private func handlePossibleCoolingElapsed() {
        guard session.phase == .cooling else { return }
        guard session.tick() else {
            armCoolingWakeIfNeeded()
            return
        }
        statusMessage = "Limit cleared — resuming the queue."
        appendEvent(.init(kind: .resumed, message: "Session ready. Resuming queued prompts."))
        if settings.notifyOnDispatch {
            NotificationService.shared.post(
                title: "Session ready",
                body: "Taskit is sending the next prompt."
            )
        }
        markDirty(.session, .events)
        flushPersistenceNow()
        if settings.autoResumeOnLimitReset, !settings.sessionFlowPaused {
            Task { await self.dispatchNextIfPossible() }
        } else if settings.sessionFlowPaused {
            statusMessage = "Limit cleared — relay is paused. Resume when you’re ready."
        }
    }

    // MARK: - Dispatch / poll

    private func dispatchNextIfPossible() async {
        guard !isBusy else { return }
        if settings.sessionFlowPaused {
            statusMessage = "Relay paused — press Start when you want the next prompt."
            return
        }
        guard session.isReadyToDispatch else {
            statusMessage = "Waiting on limit — \(remainingCoolingLabel())."
            return
        }
        guard apiKeyPresent else {
            statusMessage = "Add a Cursor API key in Settings to dispatch."
            return
        }
        guard let next = orderedGoals.first(where: { $0.status == .queued || $0.status == .waitingOnLimit }) else {
            statusMessage = completedCount > 0 ? "All prompts for today are done." : "Queue a prompt to begin."
            if completedCount > 0, session.phase != .idle {
                session.phase = .idle
                markDirty(.session)
                schedulePersist()
            }
            return
        }

        isBusy = true
        defer { isBusy = false }

        guard let idx = goals.firstIndex(where: { $0.id == next.id }) else { return }
        goals[idx].status = .dispatching
        goals[idx].startedAt = .now
        goals[idx].lastError = nil
        rebuildGoalDerivedState()
        statusMessage = "Sending “\(next.displayTitle)”…"
        markDirty(.goals)
        flushPersistenceNow()

        let client = client()
        let prompt = settings.composedPrompt(for: next)

        do {
            let agentId: String
            let runId: String
            let agentURL: String?

            if settings.dispatchMode == .continueAgent,
               let existing = settings.activeAgentId,
               !existing.isEmpty {
                let envelope = try await client.createRun(agentId: existing, prompt: prompt)
                agentId = existing
                runId = envelope.run.id
                agentURL = "https://cursor.com/agents/\(existing)"
            } else {
                let envelope = try await client.createAgent(
                    prompt: prompt,
                    name: String(next.displayTitle.prefix(100)),
                    repositoryURL: settings.repositoryURL.nilIfEmpty,
                    startingRef: settings.startingRef.nilIfEmpty,
                    modelId: settings.modelId.nilIfEmpty,
                    autoCreatePR: settings.autoCreatePR
                )
                agentId = envelope.agent.id
                runId = envelope.run?.id ?? ""
                agentURL = envelope.agent.url ?? "https://cursor.com/agents/\(agentId)"
                settings.activeAgentId = agentId
                markDirty(.settings)
            }

            goals[idx].status = .running
            goals[idx].agentId = agentId
            goals[idx].runId = runId
            goals[idx].agentURL = agentURL
            rebuildGoalDerivedState()
            session.markActive()
            session.consecutiveDispatches += 1
            appendEvent(.init(kind: .dispatched, message: "Dispatched \(next.displayTitle)", goalId: next.id))
            statusMessage = "Running “\(next.displayTitle)”."
            if settings.notifyOnDispatch {
                NotificationService.shared.post(
                    title: "Prompt sent",
                    body: next.displayTitle
                )
            }
            markDirty(.goals, .session, .events)
            flushPersistenceNow()
            startPolling(goalId: next.id, agentId: agentId, runId: runId)
        } catch CursorAPIClient.APIError.rateLimited(let signal) {
            await handleLimit(signal, for: next.id)
        } catch {
            goals[idx].status = .failed
            goals[idx].lastError = error.localizedDescription
            rebuildGoalDerivedState()
            appendEvent(.init(kind: .failed, message: error.localizedDescription, goalId: next.id))
            statusMessage = error.localizedDescription
            if let limit = LimitDetector.detect(in: error.localizedDescription) {
                await handleLimit(limit, for: next.id)
            } else {
                markDirty(.goals, .events)
                flushPersistenceNow()
            }
        }
    }

    private func handleLimit(_ signal: LimitSignal, for goalId: UUID) async {
        pollTask?.cancel()
        if let idx = goals.firstIndex(where: { $0.id == goalId }) {
            goals[idx].status = .waitingOnLimit
            goals[idx].lastError = signal.reason
            rebuildGoalDerivedState()
        }
        session.markLimitHit(reason: signal.reason, resetAt: signal.resetAt)
        appendEvent(.init(kind: .limitHit, message: signal.reason, goalId: goalId))
        statusMessage = "Hit a limit. Resuming in \(remainingCoolingLabel())."
        if settings.notifyOnLimit {
            NotificationService.shared.post(
                title: "Limit hit",
                body: "Taskit will continue in \(remainingCoolingLabel())."
            )
        }
        if let coolingUntil = session.coolingUntil,
           let goal = goals.first(where: { $0.id == goalId }) {
            NotificationService.shared.scheduleLimitResume(at: coolingUntil, goalTitle: goal.displayTitle)
        }
        markDirty(.goals, .session, .events)
        flushPersistenceNow()
        armCoolingWakeIfNeeded()
    }

    private func startPolling(goalId: UUID, agentId: String, runId: String) {
        pollTask?.cancel()
        guard !runId.isEmpty else { return }
        pollBackoffNanoseconds = Self.pollFloorNanoseconds
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.pollBackoffNanoseconds
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                let shouldContinue = await self.pollOnce(goalId: goalId, agentId: agentId, runId: runId)
                if !shouldContinue { return }
            }
        }
    }

    private func resumePollingIfNeeded() {
        guard let active = activeGoal,
              let agentId = active.agentId,
              let runId = active.runId,
              !runId.isEmpty else { return }
        startPolling(goalId: active.id, agentId: agentId, runId: runId)
    }

    /// Returns `false` when polling should stop.
    @discardableResult
    private func pollOnce(goalId: UUID, agentId: String, runId: String) async -> Bool {
        do {
            let envelope = try await client().getRun(agentId: agentId, runId: runId)
            let status = envelope.run.status.uppercased()
            guard let idx = goals.firstIndex(where: { $0.id == goalId }) else { return false }

            if Self.successStatuses.contains(status) {
                goals[idx].status = .completed
                goals[idx].completedAt = .now
                rebuildGoalDerivedState()
                appendEvent(.init(kind: .completed, message: "Finished \(goals[idx].displayTitle)", goalId: goalId))
                statusMessage = "Finished “\(goals[idx].displayTitle)”."
                if settings.notifyOnComplete {
                    NotificationService.shared.post(title: "Goal complete", body: goals[idx].displayTitle)
                }
                markDirty(.goals, .events)
                flushPersistenceNow()
                pollTask?.cancel()
                if settings.autoContinueOnFinish, !settings.sessionFlowPaused {
                    await dispatchNextIfPossible()
                } else if settings.sessionFlowPaused {
                    statusMessage = "Finished “\(goals[idx].displayTitle)”. Relay paused."
                }
                return false
            }

            if Self.failureStatuses.contains(status) {
                goals[idx].status = .failed
                goals[idx].lastError = "Run \(status.lowercased())"
                rebuildGoalDerivedState()
                appendEvent(.init(kind: .failed, message: "Run \(status.lowercased())", goalId: goalId))
                statusMessage = "Run \(status.lowercased()) for “\(goals[idx].displayTitle)”."
                markDirty(.goals, .events)
                flushPersistenceNow()
                pollTask?.cancel()
                return false
            }

            // Still running — stretch the poll interval (fast at first, gentle later).
            pollBackoffNanoseconds = min(
                Self.pollCeilNanoseconds,
                UInt64(Double(pollBackoffNanoseconds) * 1.5)
            )
            return true
        } catch CursorAPIClient.APIError.rateLimited(let signal) {
            await handleLimit(signal, for: goalId)
            return false
        } catch {
            // Transient network — keep polling, nudge backoff up slightly.
            pollBackoffNanoseconds = min(
                Self.pollCeilNanoseconds,
                UInt64(Double(pollBackoffNanoseconds) * 1.25)
            )
            return true
        }
    }

    private static let successStatuses: Set<String> = [
        "FINISHED", "COMPLETED", "SUCCESS", "DONE"
    ]
    private static let failureStatuses: Set<String> = [
        "FAILED", "ERROR", "CANCELLED", "CANCELED", "EXPIRED"
    ]

    // MARK: - Persistence / derived state

    private func rebuildGoalDerivedState() {
        orderedGoals = goals.sorted { $0.sortIndex < $1.sortIndex }
        completedCount = 0
        queuedCount = 0
        for goal in goals {
            switch goal.status {
            case .completed:
                completedCount += 1
            case .queued, .waitingOnLimit:
                queuedCount += 1
            default:
                break
            }
        }
    }

    private func reindex() {
        for (idx, goal) in orderedGoals.enumerated() {
            if let i = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[i].sortIndex = idx
            }
        }
    }

    private func appendEvent(_ event: DispatchEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events.removeLast(events.count - Self.maxEvents)
        }
    }

    private func markDirty(_ keys: PersistKey...) {
        dirty.formUnion(keys)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.persistDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPersistenceNow()
        }
    }

    private func flushPersistenceNow() {
        persistTask?.cancel()
        let snapshot = dirty
        dirty.removeAll(keepingCapacity: true)
        guard !snapshot.isEmpty else { return }

        if snapshot.contains(.goals) {
            Persistence.save(goals, to: Persistence.goalsURL)
        }
        if snapshot.contains(.settings) {
            Persistence.save(settings, to: Persistence.settingsURL)
        }
        if snapshot.contains(.session) {
            Persistence.save(session, to: Persistence.sessionURL)
        }
        if snapshot.contains(.events) {
            Persistence.save(events, to: Persistence.eventsURL)
        }
    }

    private func client() -> CursorAPIClient {
        if let cachedClient, cachedClient.apiKey == apiKey {
            return cachedClient
        }
        let fresh = CursorAPIClient(apiKey: apiKey)
        cachedClient = fresh
        return fresh
    }

    private func invalidateClient() {
        cachedClient = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
