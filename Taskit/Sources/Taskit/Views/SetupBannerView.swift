import SwiftUI

struct SetupBannerView: View {
    let issues: [String]
    var onOpenSettings: () -> Void

    var body: some View {
        GlassSurface(cornerRadius: 16, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Almost ready")
                        .font(.system(size: 12.5, weight: .medium, design: .default))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Spacer()
                    Button("Settings", action: onOpenSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text(issue)
                        .font(.system(size: 11.5, weight: .regular, design: .default))
                        .foregroundStyle(TaskitTheme.hush)
                }
            }
        }
        .transition(.opacity)
    }
}
