import SwiftUI

enum TaskitTheme {
    // Quiet glass — near-monochrome. A background utility, not a destination.
    static let accent = Color.white.opacity(0.92)
    static let accentDeep = Color.white.opacity(0.55)
    static let accentSoft = Color.white.opacity(0.72)
    static let warmReady = Color.white.opacity(0.78)
    static let danger = Color.white.opacity(0.65)
    static let mist = Color.white.opacity(0.78)
    static let hush = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.10)
    static let glassFill = Color.white.opacity(0.05)

    static let springSnappy = Animation.spring(response: 0.36, dampingFraction: 0.9)
    static let springSoft = Animation.spring(response: 0.5, dampingFraction: 0.92)
    static let appear = Animation.easeOut(duration: 0.28)

    static var brandFont: Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    static var displayFont: Font {
        .system(size: 30, weight: .medium, design: .default)
    }

    static var bodyFont: Font {
        .system(size: 12.5, weight: .regular, design: .default)
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
            Color(red: 0.08, green: 0.08, blue: 0.085)

            // Barely-there soft light — no color cast.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 160
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 90, y: -120)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.035), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 140
                    )
                )
                .frame(width: 260, height: 260)
                .offset(x: -100, y: 150)
        }
        .ignoresSafeArea()
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - Glass primitives

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 18
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
                            .fill(Color.white.opacity(emphasized ? 0.07 : 0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(emphasized ? 0.16 : 0.10), lineWidth: 1)
                    }
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(emphasized ? Color.white.opacity(0.9) : TaskitTheme.hush)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            Circle().strokeBorder(TaskitTheme.hairline, lineWidth: 1)
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
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(isProminent ? Color.black.opacity(0.82) : TaskitTheme.mist)
            .background {
                Capsule(style: .continuous)
                    .fill(isProminent ? Color.white.opacity(0.92) : Color.white.opacity(0.07))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(isProminent ? 0.2 : 0.1), lineWidth: 1)
                    }
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
                .font(.system(size: 12, weight: .medium, design: .default))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(TaskitTheme.mist)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            Capsule().strokeBorder(TaskitTheme.hairline, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppearModifier: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
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
            .font(.system(size: 10, weight: .medium, design: .default))
            .tracking(0.8)
            .foregroundStyle(TaskitTheme.hush)
    }
}
