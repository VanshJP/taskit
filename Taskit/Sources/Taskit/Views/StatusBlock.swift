import SwiftUI
import TaskitCore

/// One compact block that says what the queue is doing and offers the one action that matters.
@MainActor
struct StatusBlock: View {
    let app: AppModel

    private var engine: RelayEngine { app.engine }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(Status(engine: engine, now: context.date))
        }
    }

    private func content(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                icon(status.phase)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(status.phase == .waiting ? Theme.waitingText : Color.primary)
                    Text(status.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButton(status.phase)
            }

            if let progress = status.progress {
                ProgressBar(value: progress, tint: status.phase == .waiting ? Theme.waitingBar : .accentColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(status.phase == .waiting ? Theme.waitingFill : Theme.statusFill)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func icon(_ phase: Phase) -> some View {
        switch phase {
        case .running:
            ProgressView().controlSize(.small)
        case .waiting:
            Image(systemName: "hourglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.waitingText)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 15))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19))
                .foregroundStyle(Color.accentColor)
        case .empty, .idle:
            Image(systemName: "list.bullet")
                .font(.system(size: 15, weight: .medium))
        }
    }

    @ViewBuilder
    private func actionButton(_ phase: Phase) -> some View {
        switch phase {
        case .idle:
            Button("Start") { engine.start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
        case .paused where engine.hasPending:
            Button("Resume") { engine.start() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
        case .waiting:
            Button("Try now") { engine.tryNow() }
                .buttonStyle(.bordered)
                .help("Skip the wait and send the next prompt now")
        case .done:
            Button("Clear") { engine.clearFinished() }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }
}

/// Copy for the status block, derived from the engine.
private struct Status {
    let phase: Phase
    let title: String
    let subtitle: String
    let progress: Double?

    @MainActor
    init(engine: RelayEngine, now: Date) {
        phase = engine.phase
        let total = engine.items.count
        let done = engine.doneCount
        let failed = engine.failedCount
        let finished = done + failed
        let pending = engine.pendingCount

        switch engine.phase {
        case .empty:
            title = "Nothing queued"
            subtitle = "Add prompts below. Taskit runs them in order and waits out usage limits."
            progress = nil

        case .idle:
            title = "\(pending) queued"
            subtitle = finished > 0
                ? "\(finished) finished so far. Press Start to continue."
                : "Runs one after another in \(engine.settings.projectDisplayPath)"
            progress = nil

        case .running:
            title = "\(finished) of \(total) done"
            if let running = engine.runningItem, let started = running.startedAt {
                subtitle = "Claude is on prompt \(finished + 1), started \(DurationFormat.short(now.timeIntervalSince(started))) ago"
            } else {
                subtitle = "Starting the next prompt…"
            }
            progress = total > 0 ? Double(finished) / Double(total) : 0

        case .waiting:
            title = "Usage limit reached"
            if let limit = engine.limit {
                let remaining = DurationFormat.short(limit.resetsAt.timeIntervalSince(now))
                subtitle = "Continues on its own at \(Format.time(limit.resetsAt, now: now)) (in \(remaining))"
                progress = limit.progress(at: now)
            } else {
                subtitle = "Continues on its own when the limit resets"
                progress = nil
            }

        case .paused:
            title = "Paused"
            if let notice = engine.notice {
                subtitle = notice
            } else if engine.runningItem != nil {
                subtitle = "The current prompt will finish. Nothing new starts until you resume."
            } else if let limit = engine.limit, limit.resetsAt > now {
                subtitle = "\(pending) queued. The usage limit resets at \(Format.time(limit.resetsAt, now: now))."
            } else {
                subtitle = "\(pending) queued. Nothing starts until you resume."
            }
            progress = total > 0 ? Double(finished) / Double(total) : nil

        case .done:
            title = failed == 0 ? "All \(total) done" : "\(done) done, \(failed) failed"
            if let last = engine.items.compactMap(\.finishedAt).max() {
                subtitle = "Finished at \(Format.time(last, now: now))"
            } else {
                subtitle = "Nothing left in the queue"
            }
            progress = 1
        }
    }
}

@MainActor
private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}
