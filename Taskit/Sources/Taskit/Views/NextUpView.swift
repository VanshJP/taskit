import SwiftUI
import TaskitCore

struct NextUpView: View {
    let goal: Goal?
    var isPaused: Bool
    var onCopy: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: 18, padding: 13, emphasized: goal != nil && !isPaused) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [TaskitTheme.accent, TaskitTheme.warmReady.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: isPaused ? "Paused · next" : "Next up")
                    if let goal {
                        Text(goal.displayTitle)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineLimit(1)
                        Text(goal.prompt)
                            .font(.system(size: 11.5, weight: .regular, design: .rounded))
                            .foregroundStyle(TaskitTheme.hush)
                            .lineLimit(2)
                    } else {
                        Text("Queue a prompt to arm the relay.")
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(TaskitTheme.hush)
                    }
                }
                Spacer(minLength: 0)
                if goal != nil {
                    GlassIconButton(systemName: "doc.on.doc", help: "Copy composed prompt", action: onCopy)
                }
            }
        }
    }
}
