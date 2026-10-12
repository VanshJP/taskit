import SwiftUI
import TaskitCore

struct NextUpView: View {
    let goal: Goal?
    var isPaused: Bool
    var onCopy: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: 16, padding: 12, emphasized: false) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: isPaused ? "Paused · next" : "Next up")
                    if let goal {
                        Text(goal.displayTitle)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                        Text(goal.prompt)
                            .font(.system(size: 11.5, weight: .regular, design: .default))
                            .foregroundStyle(TaskitTheme.hush)
                            .lineLimit(2)
                    } else {
                        Text("Queue a prompt to arm the relay.")
                            .font(.system(size: 12.5, weight: .regular, design: .default))
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
