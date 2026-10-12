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
        let accent = phaseAccent

        return VStack(spacing: 18) {
            HeroRing(
                progress: progress,
                phaseAccent: accent,
                symbol: heroSymbol,
                fraction: "\(engine.completedCount)/\(max(engine.goals.count, 0))",
                pulse: engine.session.phase == .active
            )
            .animation(TaskitTheme.springSoft, value: progress)

            VStack(spacing: 8) {
                StatusPill(text: phaseLabel, tone: pillTone)

                Text(headline)
                    .font(TaskitTheme.displayFont)
                    .foregroundStyle(Color.white.opacity(0.96))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(TaskitTheme.springSnappy, value: headline)

                Text(subline)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(TaskitTheme.hush)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var phaseLabel: String {
        if engine.isPaused { return "Paused" }
        return engine.session.phase.label
    }

    private var phaseAccent: Color {
        if engine.isPaused { return TaskitTheme.warmReady }
        switch engine.session.phase {
        case .ready: return TaskitTheme.warmReady
        case .cooling: return TaskitTheme.warmReady
        case .active: return TaskitTheme.accent
        case .idle: return TaskitTheme.accentSoft
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
        if engine.isPaused {
            return "Auto-relay is holding · resume when you want the next prompt"
        }
        switch engine.session.phase {
        case .cooling:
            return "Limit window · the next prompt fires on its own"
        case .ready:
            return "Window cleared · relay continues"
        case .active:
            return engine.statusMessage
        case .idle:
            return engine.queuedCount == 0
                ? "Queue today’s prompts. Walk away."
                : engine.statusMessage
        }
    }

    private var pillTone: StatusPill.Tone {
        if engine.isPaused { return .cooling }
        switch engine.session.phase {
        case .active: return .active
        case .ready: return .ready
        case .cooling: return .cooling
        case .idle: return .neutral
        }
    }

    private var heroSymbol: String {
        if engine.isPaused { return "pause.fill" }
        switch engine.session.phase {
        case .cooling: return "hourglass"
        case .ready: return "sparkles"
        case .active: return "guidepost.fill"
        case .idle: return "moon.stars"
        }
    }
}
