import SwiftUI
import TaskitCore

struct SessionHeroView: View {
    @Bindable var engine: RelayEngine

    private var ringProgress: Double {
        switch engine.session.phase {
        case .cooling:
            return engine.session.coolingProgress
        case .active:
            let total = max(1, engine.goals.count)
            return Double(engine.completedCount) / Double(total)
        case .ready:
            return 1
        case .idle:
            return engine.goals.isEmpty ? 0 : Double(engine.completedCount) / Double(max(1, engine.goals.count))
        }
    }

    private var headline: String {
        switch engine.session.phase {
        case .cooling: return engine.remainingCoolingLabel
        case .ready: return "Ready"
        case .active: return engine.activeGoal?.displayTitle ?? "In session"
        case .idle: return engine.queuedGoals.isEmpty ? "Taskit" : "\(engine.queuedGoals.count) queued"
        }
    }

    private var subline: String {
        switch engine.session.phase {
        case .cooling:
            return "Limit window · next prompt fires automatically"
        case .ready:
            return "Window cleared · relay will continue"
        case .active:
            return engine.statusMessage
        case .idle:
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

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(
                        progress: ringProgress,
                        lineWidth: 7,
                        tint: engine.session.phase == .ready ? TaskitTheme.warmReady : TaskitTheme.accent
                    )
                    .frame(width: 78, height: 78)

                    VStack(spacing: 2) {
                        Image(systemName: heroSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TaskitTheme.accent)
                            .symbolEffect(.pulse, options: .repeating, isActive: engine.session.phase == .active || engine.session.phase == .cooling)
                        Text("\(engine.completedCount)/\(engine.goals.count)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    StatusPill(text: engine.session.phase.label, tone: pillTone)
                    Text(headline)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: headline)
                    Text(subline)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
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
