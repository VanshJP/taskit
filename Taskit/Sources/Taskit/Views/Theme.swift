import SwiftUI

enum TaskitTheme {
    // Nocturne Tide — ink depth, luminous seafoam, champagne signal.
    static let accent = Color(red: 0.45, green: 0.86, blue: 0.78)
    static let accentDeep = Color(red: 0.16, green: 0.52, blue: 0.48)
    static let accentSoft = Color(red: 0.55, green: 0.78, blue: 0.74)
    static let warmReady = Color(red: 0.96, green: 0.78, blue: 0.42)
    static let danger = Color(red: 0.93, green: 0.46, blue: 0.42)
    static let mist = Color.white.opacity(0.72)
    static let hush = Color.white.opacity(0.48)
    static let hairline = Color.white.opacity(0.12)
    static let glassFill = Color.white.opacity(0.055)

    static let springSnappy = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let springSoft = Animation.spring(response: 0.55, dampingFraction: 0.9)
    static let appear = Animation.spring(response: 0.5, dampingFraction: 0.88)

    static var brandFont: Font {
        .system(size: 28, weight: .semibold, design: .serif)
    }

    static var displayFont: Font {
        .system(size: 34, weight: .semibold, design: .serif)
    }

    static var bodyFont: Font {
        .system(size: 12.5, weight: .medium, design: .rounded)
    }

    static var atmosphere: some View {
        AtmosphereBackground()
            .equatable()
    }
}

// MARK: - Atmosphere

private struct AtmosphereBackground: View, Equatable {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.12),
                    Color(red: 0.05, green: 0.07, blue: 0.09),
                    Color(red: 0.08, green: 0.11, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft luminous orbs — depth without purple/glow cliché overload.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [TaskitTheme.accent.opacity(0.34), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: 120, y: -100)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [TaskitTheme.warmReady.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .offset(x: -110, y: 160)

            // Fine grain so glass never feels flat.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            .clear,
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - Glass primitives

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 14
    var emphasized = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(emphasized ? 0.14 : 0.09),
                                        Color.white.opacity(0.02),
                                        TaskitTheme.accent.opacity(emphasized ? 0.08 : 0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(0.14)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.22), radius: emphasized ? 18 : 10, y: emphasized ? 10 : 6)
            }
    }
}

/// Back-compat alias used across views.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSurface(padding: padding, content: content)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var help: String? = nil
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(emphasized ? TaskitTheme.accent : TaskitTheme.mist)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(PressableButtonStyle())
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
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isProminent ? Color(red: 0.05, green: 0.10, blue: 0.10) : TaskitTheme.mist)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isProminent
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    TaskitTheme.accent.opacity(1),
                                    TaskitTheme.accentSoft.opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                          )
                        : AnyShapeStyle(Color.white.opacity(0.07))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isProminent ? 0.35 : 0.14),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: isProminent ? TaskitTheme.accent.opacity(0.28) : .clear,
                        radius: 14,
                        y: 6
                    )
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct GhostCapsuleButton: View {
    let title: String
    var systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(TaskitTheme.mist)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            Capsule()
                                .strokeBorder(TaskitTheme.hairline, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(TaskitTheme.springSnappy, value: configuration.isPressed)
    }
}

struct AppearModifier: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(TaskitTheme.appear.delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func taskitAppear(delay: Double = 0) -> some View {
        modifier(AppearModifier(delay: delay))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(TaskitTheme.hush)
    }
}
