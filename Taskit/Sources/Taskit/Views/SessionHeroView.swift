import SwiftUI
import TaskitCore

struct SessionHeroView: View {
    @Bindable var engine: RelayEngine

    var body: some View {
        if engine.session.phase == .cooling {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                hero(at: context.date)
            }
        } else {
            hero(at: .now)
        }
    }

    private func hero(at now: Date) -> some View {
        let progress = ringProgress(at: now)
        let headline = headline(at: now)

        return GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(
                        progress: progress,
                        lineWidth: 7,
                        tint: engine.session.phase == .ready ? TaskitTheme.warmReady : TaskitTheme.accent
                    )
                    .frame(width: 78, height: 78)
                    .animation(.easeInOut(duration: 0.45), value: progress)

                    VStack(spacing: 2) {
                        Image(systemName: heroSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TaskitTheme.accent)
                            // Pulse only while a run is live — not for multi-hour cool-downs.
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: engine.session.phase == .active
                            )
                        Text("\(engine.completedCount)/\(engine.goals.count)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: engine.session.phase.label, tone: pillTone)
                    Text(headline)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(subline)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func ringProgress(at now: Date) -> Double {
        switch engine.session.phase {
        case .cooling:
            return engine.coolingProgress(at: now)
        case .active, .idle:
            let total = max(1, engine.goals.count)
            return Double(engine.completedCount) / Double(total)
        case .ready:
            return 1
        }
    }

    private func headline(at now: Date) -> String {
        switch engine.session.phase {
        case .cooling: return engine.remainingCoolingLabel(at: now)
        case .ready: return "Ready"
        case .active: return engine.activeGoal?.displayTitle ?? "In session"
        case .idle: return engine.queuedCount == 0 ? "Taskit" : "\(engine.queuedCount) queued"
        }
    }

    private var subline: String {
        switch engine.session.phase {
        case .cooling:
            return "Limit window · next prompt fires automatically"
        case .ready:
            return "Window cleared · relay will continue"
        case .active, .idle:
            return engine.statusMessage
        }
    }

    private var pillTone: StatusPill.Tone {
        switch engine.session.phase {
        case .active: return .active
        case .ready: return .ready
        case .cooling: return .cooling
        case .idle: return .neutral
        }
    }

    private var heroSymbol: String {
        switch engine.session.phase {
        case .cooling: return "hourglass"
        case .ready: return "sparkles"
        case .active: return "guidepost.fill"
        case .idle: return "moon.stars"
        }
    }
}
