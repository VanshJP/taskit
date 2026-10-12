import SwiftUI

struct StatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, active, ready, cooling, danger

        var foreground: Color {
            switch self {
            case .neutral: return TaskitTheme.hush
            case .active: return Color(red: 0.08, green: 0.22, blue: 0.20)
            case .ready: return Color(red: 0.28, green: 0.18, blue: 0.04)
            case .cooling: return TaskitTheme.warmReady.opacity(0.95)
            case .danger: return TaskitTheme.danger
            }
        }

        var background: AnyShapeStyle {
            switch self {
            case .neutral:
                return AnyShapeStyle(Color.white.opacity(0.07))
            case .active:
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [TaskitTheme.accent.opacity(0.95), TaskitTheme.accentSoft.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            case .ready:
                return AnyShapeStyle(TaskitTheme.warmReady.opacity(0.9))
            case .cooling:
                return AnyShapeStyle(TaskitTheme.warmReady.opacity(0.16))
            case .danger:
                return AnyShapeStyle(TaskitTheme.danger.opacity(0.18))
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(tone.background)
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
    }
}
