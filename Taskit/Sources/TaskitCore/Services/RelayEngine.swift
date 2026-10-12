import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class RelayEngine {
    public var goals: [Goal] = []
    public var settings: AppSettings = .default
    public var session: SessionClock = .init()
    public var events: [DispatchEvent] = []
    public var isBusy = false
    public var statusMessage = "Queue a few prompts for the day."
    public var apiKeyPresent = false

    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var apiKey: String = ""

    public var queuedGoals: [Goal] {
        goals
            .filter { $0.status == .queued || $0.status == .waitingOnLimit }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    public var activeGoal: Goal? {
        goals.first { $0.status == .running || $0.status == .dispatching }
    }

    public var completedCount: Int {
        goals.filter { $0.status == .completed }.count
    }

    public var menuBarTitle: String {
        switch session.phase {
        case .cooling:
            return remainingCoolingLabel
        case .ready:
            return "Ready"
        case .active:
            return activeGoal?.displayTitle.prefix(18).description ?? "Active"
        case .idle:
            return queuedGoals.isEmpty ? "Taskit" : "\(queuedGoals.count) left"
        }
    }

    public var remainingCoolingLabel: String {
        formatDuration(session.remainingCooling)
    }

    public init() {
        reload()
        startTicker()
    }

    public func reload() {
        goals = Persistence.load([Goal].self, from: Persistence.goalsURL, fallback: [])
        settings = Persistence.load(AppSettings.self, from: Persistence.settingsURL, fallback: .default)
        session = Persistence.load(SessionClock.self, from: Persistence.sessionURL, fallback: .init())
        events = Persistence.load([DispatchEvent].self, from: Persistence.eventsURL, fallback: [])
        session.windowSeconds = settings.sessionWindowSeconds
        apiKey = KeychainStore.loadAPIKey() ?? ""
        apiKeyPresent = !apiKey.isEmpty
        if session.tick() {
            statusMessage = "Limit window cleared. Ready to continue."
        }
        resumePollingIfNeeded()
    }

    public func persist() {
        Persistence.save(goals, to: Persistence.goalsURL)
        Persistence.save(settings, to: Persistence.settingsURL)
        Persistence.save(session, to: Persistence.sessionURL)
        Persistence.save(Array(events.prefix(80)), to: Persistence.eventsURL)
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
    }

    public func addGoal(title: String, prompt: String) {
        let nextIndex = (goals.map(\.sortIndex).max() ?? -1) + 1
        let goal = Goal(title: title, prompt: prompt, sortIndex: nextIndex)
        goals.append(goal)
        persist()
        statusMessage = "Added “\(goal.displayTitle)”."
    }

    public func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        reindex()
        persist()
    }

    public func moveGoals(from source: IndexSet, to destination: Int) {
        var ordered = goals.sorted { $0.sortIndex < $1.sortIndex }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (idx, item) in ordered.enumerated() {
            if let i = goals.firstIndex(where: { $0.id == item.id }) {
                goals[i].sortIndex = idx
            }
        }
        persist()
    }

    public func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        session.windowSeconds = settings.sessionWindowSeconds
        LaunchAtLogin.setEnabled(settings.launchAtLogin)
        persist()
    }

    public func startRelay() async {
        guard !isBusy else { return }
        if session.phase == .cooling, !session.isReadyToDispatch {
            statusMessage = "Still cooling — \(remainingCoolingLabel) left."
            return
        }
        if session.phase == .ready || session.phase == .cooling {
            session.markActive()
        }
        await dispatchNextIfPossible()
    }

    public func markLimitHit(customHours: Double? = nil) {
        let hours = customHours ?? settings.sessionWindowHours
        session.windowSeconds = max(15 * 60, hours * 3600)
        session.markLimitHit(reason: "Marked manually — waiting for the next window.")
        if let active = activeGoal, let idx = goals.firstIndex(where: { $0.id == active.id }) {
            goals[idx].status = .waitingOnLimit
        }
        if let next = queuedGoals.first {
            NotificationService.shared.scheduleLimitResume(
                at: session.coolingUntil ?? Date().addingTimeInterval(session.windowSeconds),
                goalTitle: next.displayTitle
            )
        }
        appendEvent(.init(kind: .limitHit, message: "Session marked as limited. Auto-resume armed."))
        statusMessage = "Cooling for \(formatDuration(session.windowSeconds)). Next prompt will fire automatically."
        if settings.notifyOnLimit {
            NotificationService.shared.post(
                title: "Limit window started",
                body: "Taskit will re-prompt in \(formatDuration(session.windowSeconds))."
            )
        }
        persist()
    }

    public func skipGoal(_ goal: Goal) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].status = .skipped
        goals[idx].completedAt = .now
        appendEvent(.init(kind: .skipped, message: "Skipped \(goal.displayTitle)", goalId: goal.id))
        persist()
    }

    public func resetDay() {
        pollTask?.cancel()
        goals = []
        session.markIdle()
        events = []
        settings.activeAgentId = nil
        statusMessage = "Fresh day. Queue your prompts."
        persist()
    }

    public func openActiveAgent() {
        guard let urlString = activeGoal?.agentURL ?? goals.last(where: { $0.agentURL != nil })?.agentURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Internals

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.handleTick()
                }
            }
        }
    }

    private func handleTick() {
        let becameReady = session.tick()
        if becameReady {
            statusMessage = "Limit cleared — resuming the queue."
            appendEvent(.init(kind: .resumed, message: "Session ready. Resuming queued prompts."))
            if settings.notifyOnDispatch {
                NotificationService.shared.post(
                    title: "Session ready",
                    body: "Taskit is sending the next prompt."
                )
            }
            persist()
            if settings.autoResumeOnLimitReset {
                Task { await self.dispatchNextIfPossible() }
            }
        } else if session.phase == .cooling {
            // Keep UI live without thrashing disk.
        }
    }

    private func dispatchNextIfPossible() async {
        guard !isBusy else { return }
        guard session.isReadyToDispatch else {
            statusMessage = "Waiting on limit — \(remainingCoolingLabel)."
            return
        }
        guard apiKeyPresent else {
            statusMessage = "Add a Cursor API key in Settings to dispatch."
            return
        }
        guard let next = goals
            .sorted(by: { $0.sortIndex < $1.sortIndex })
            .first(where: { $0.status == .queued || $0.status == .waitingOnLimit })
        else {
            statusMessage = completedCount > 0 ? "All prompts for today are done." : "Queue a prompt to begin."
            session.phase = completedCount > 0 ? .idle : session.phase
            persist()
            return
        }

        isBusy = true
        defer { isBusy = false }

        guard let idx = goals.firstIndex(where: { $0.id == next.id }) else { return }
        goals[idx].status = .dispatching
        goals[idx].startedAt = .now
        goals[idx].lastError = nil
        statusMessage = "Sending “\(next.displayTitle)”…"
        persist()

        let client = CursorAPIClient(apiKey: apiKey)
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
            }

            goals[idx].status = .running
            goals[idx].agentId = agentId
            goals[idx].runId = runId
            goals[idx].agentURL = agentURL
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
            persist()
            startPolling(goalId: next.id, agentId: agentId, runId: runId)
        } catch CursorAPIClient.APIError.rateLimited(let signal) {
            await handleLimit(signal, for: next.id)
        } catch {
            goals[idx].status = .failed
            goals[idx].lastError = error.localizedDescription
            appendEvent(.init(kind: .failed, message: error.localizedDescription, goalId: next.id))
            statusMessage = error.localizedDescription
            if let limit = LimitDetector.detect(in: error.localizedDescription) {
                await handleLimit(limit, for: next.id)
            }
            persist()
        }
    }

    private func handleLimit(_ signal: LimitSignal, for goalId: UUID) async {
        if let idx = goals.firstIndex(where: { $0.id == goalId }) {
            goals[idx].status = .waitingOnLimit
            goals[idx].lastError = signal.reason
        }
        session.markLimitHit(reason: signal.reason, resetAt: signal.resetAt)
        appendEvent(.init(kind: .limitHit, message: signal.reason, goalId: goalId))
        statusMessage = "Hit a limit. Resuming in \(remainingCoolingLabel)."
        if settings.notifyOnLimit {
            NotificationService.shared.post(
                title: "Limit hit",
                body: "Taskit will continue in \(remainingCoolingLabel)."
            )
        }
        if let coolingUntil = session.coolingUntil,
           let goal = goals.first(where: { $0.id == goalId }) {
            NotificationService.shared.scheduleLimitResume(at: coolingUntil, goalTitle: goal.displayTitle)
        }
        persist()
    }

    private func startPolling(goalId: UUID, agentId: String, runId: String) {
        pollTask?.cancel()
        guard !runId.isEmpty else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let self else { return }
                await self.pollOnce(goalId: goalId, agentId: agentId, runId: runId)
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

    private func pollOnce(goalId: UUID, agentId: String, runId: String) async {
        let client = CursorAPIClient(apiKey: apiKey)
        do {
            let envelope = try await client.getRun(agentId: agentId, runId: runId)
            let status = envelope.run.status.uppercased()
            guard let idx = goals.firstIndex(where: { $0.id == goalId }) else { return }

            if ["FINISHED", "COMPLETED", "SUCCESS", "DONE"].contains(status) {
                goals[idx].status = .completed
                goals[idx].completedAt = .now
                appendEvent(.init(kind: .completed, message: "Finished \(goals[idx].displayTitle)", goalId: goalId))
                statusMessage = "Finished “\(goals[idx].displayTitle)”."
                if settings.notifyOnComplete {
                    NotificationService.shared.post(title: "Goal complete", body: goals[idx].displayTitle)
                }
                persist()
                pollTask?.cancel()
                if settings.autoContinueOnFinish {
                    await dispatchNextIfPossible()
                }
            } else if ["FAILED", "ERROR", "CANCELLED", "CANCELED", "EXPIRED"].contains(status) {
                goals[idx].status = .failed
                goals[idx].lastError = "Run \(status.lowercased())"
                appendEvent(.init(kind: .failed, message: "Run \(status.lowercased())", goalId: goalId))
                statusMessage = "Run \(status.lowercased()) for “\(goals[idx].displayTitle)”."
                persist()
                pollTask?.cancel()
            }
        } catch CursorAPIClient.APIError.rateLimited(let signal) {
            await handleLimit(signal, for: goalId)
            pollTask?.cancel()
        } catch {
            // Transient network errors — keep polling.
        }
    }

    private func reindex() {
        let ordered = goals.sorted { $0.sortIndex < $1.sortIndex }
        for (idx, goal) in ordered.enumerated() {
            if let i = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[i].sortIndex = idx
            }
        }
    }

    private func appendEvent(_ event: DispatchEvent) {
        events.insert(event, at: 0)
        if events.count > 80 {
            events = Array(events.prefix(80))
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
