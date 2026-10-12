import SwiftUI
import TaskitCore

struct NextUpView: View {
    let goal: Goal?
    var isPaused: Bool
    var onCopy: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPaused ? "Paused · next up" : "Next up")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let goal {
                        Text(goal.displayTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(goal.prompt)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("Queue a prompt to arm the relay.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if goal != nil {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .help("Copy composed prompt (day goal + next step)")
                }
            }
        }
    }
}
