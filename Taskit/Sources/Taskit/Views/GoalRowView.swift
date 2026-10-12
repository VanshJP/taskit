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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusGlyph
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.displayTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(goal.status == .completed ? .secondary : .primary)
                    .strikethrough(goal.status == .completed || goal.status == .skipped)
                Text(goal.prompt)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let error = goal.lastError, goal.status == .failed || goal.status == .waitingOnLimit {
                    Text(error)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(TaskitTheme.danger.opacity(0.9))
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
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TaskitTheme.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(TaskitTheme.danger)
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
