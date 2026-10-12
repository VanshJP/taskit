import SwiftUI
import TaskitCore

struct SetupBannerView: View {
    let issues: [String]
    var onOpenSettings: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(TaskitTheme.warmReady)
                    Text("Almost ready")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Settings", action: onOpenSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(TaskitTheme.accent)
                }
                ForEach(issues, id: \.self) { issue in
                    HStack(spacing: 8) {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: 10, height: 10)
                        Text(issue)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
