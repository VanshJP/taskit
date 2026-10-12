import SwiftUI
import TaskitCore

struct GoalRowView: View {
    let goal: Goal
    var onSkip: () -> Void
    var onDelete: () -> Void
    var onOpen: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onRequeue: () -> Void

    private var isDimmed: Bool {
        goal.status == .completed || goal.status == .skipped
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusGlyph
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.displayTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDimmed ? TaskitTheme.hush : Color.white.opacity(0.94))
                    .strikethrough(isDimmed, color: TaskitTheme.hush.opacity(0.5))
                Text(goal.prompt)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundStyle(TaskitTheme.hush)
                    .lineLimit(2)
                if let error = goal.lastError, goal.status == .failed || goal.status == .waitingOnLimit {
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(TaskitTheme.danger.opacity(0.95))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Edit…", action: onEdit)
                Button("Copy composed prompt", action: onCopy)
                if goal.agentURL != nil {
                    Button("Open in Cursor", action: onOpen)
                }
                if goal.status == .queued || goal.status == .waitingOnLimit {
                    Button("Skip", action: onSkip)
                }
                if goal.status == .failed || goal.status == .skipped || goal.status == .completed {
                    Button("Requeue", action: onRequeue)
                }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TaskitTheme.hush)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .background {
            if goal.status == .running || goal.status == .dispatching {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.displayTitle), \(goal.status.label)")
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch goal.status {
        case .queued:
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
        case .waitingOnLimit:
            Image(systemName: "hourglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TaskitTheme.warmReady)
        case .dispatching, .running:
            ProgressView()
                .controlSize(.small)
                .tint(TaskitTheme.accent)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TaskitTheme.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(TaskitTheme.danger)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 10))
                .foregroundStyle(TaskitTheme.hush)
        }
    }
}
