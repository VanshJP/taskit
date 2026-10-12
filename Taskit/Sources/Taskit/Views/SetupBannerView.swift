import SwiftUI

struct SetupBannerView: View {
    let issues: [String]
    var onOpenSettings: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: 18, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(TaskitTheme.warmReady)
                    Text("Almost ready")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Spacer()
                    Button("Settings", action: onOpenSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(TaskitTheme.accent)
                }
                ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(TaskitTheme.hush)
                            .monospacedDigit()
                        Text(issue)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(TaskitTheme.mist)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
