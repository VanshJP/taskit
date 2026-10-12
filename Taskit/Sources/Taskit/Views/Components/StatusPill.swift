import SwiftUI

struct StatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral, active, ready, cooling, danger

        var foreground: Color {
            switch self {
            case .neutral, .cooling, .danger:
                return TaskitTheme.hush
            case .active, .ready:
                return Color.white.opacity(0.85)
            }
        }

        var background: Color {
            switch self {
            case .neutral, .cooling:
                return Color.white.opacity(0.06)
            case .active, .ready:
                return Color.white.opacity(0.12)
            case .danger:
                return Color.white.opacity(0.08)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .default))
            .tracking(0.2)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(tone.background)
                    .overlay {
                        Capsule().strokeBorder(TaskitTheme.hairline, lineWidth: 1)
                    }
            }
    }
}
