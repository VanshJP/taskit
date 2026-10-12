import SwiftUI

struct StatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, active, ready, cooling, danger

        var foreground: Color {
            switch self {
            case .neutral: return .secondary
            case .active: return TaskitTheme.accentDeep
            case .ready: return Color(red: 0.45, green: 0.30, blue: 0.05)
            case .cooling: return .secondary
            case .danger: return TaskitTheme.danger
            }
        }

        var background: Color {
            switch self {
            case .neutral: return Color.white.opacity(0.08)
            case .active: return TaskitTheme.accent.opacity(0.22)
            case .ready: return TaskitTheme.warmReady.opacity(0.28)
            case .cooling: return Color.white.opacity(0.08)
            case .danger: return TaskitTheme.danger.opacity(0.18)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tone.background, in: Capsule())
    }
}
