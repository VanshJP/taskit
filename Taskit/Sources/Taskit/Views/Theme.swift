import SwiftUI

enum TaskitTheme {
    /// Soft seafoam — calm, distinct from the usual AI purple cluster.
    static let accent = Color(red: 0.35, green: 0.72, blue: 0.68)
    static let accentDeep = Color(red: 0.18, green: 0.48, blue: 0.46)
    static let warmReady = Color(red: 0.93, green: 0.72, blue: 0.38)
    static let danger = Color(red: 0.90, green: 0.42, blue: 0.38)
    static let ink = Color.primary.opacity(0.92)
    static let hush = Color.secondary.opacity(0.85)

    static var panelGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.14),
                Color.white.opacity(0.04),
                accent.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Rasterized once — soft blurs are expensive if SwiftUI recomposites them every frame.
    static var atmosphere: some View {
        AtmosphereBackground()
            .equatable()
    }
}

private struct AtmosphereBackground: View, Equatable {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.14, blue: 0.16),
                    Color(red: 0.07, green: 0.10, blue: 0.12),
                    Color(red: 0.12, green: 0.16, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(TaskitTheme.accent.opacity(0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 110, y: -80)
            Circle()
                .fill(TaskitTheme.warmReady.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 50)
                .offset(x: -90, y: 120)
        }
        .ignoresSafeArea()
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(TaskitTheme.panelGradient)
                    }
            }
    }
}

struct GlassIconButton: View {
    let systemName: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

struct PrimaryGlassButton: View {
    let title: String
    var systemImage: String? = nil
    var isProminent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(isProminent ? Color.black.opacity(0.88) : Color.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(isProminent ? TaskitTheme.accent : Color.white.opacity(0.08))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(isProminent ? 0.25 : 0.14), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
