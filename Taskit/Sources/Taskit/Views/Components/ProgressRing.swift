import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var tint: Color = TaskitTheme.accent

    var body: some View {
        let clamped = min(1, max(0, progress))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [
                            tint.opacity(0.2),
                            tint,
                            TaskitTheme.warmReady.opacity(0.95),
                            tint.opacity(0.75)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.32), radius: 8, y: 0)
        }
    }
}

struct HeroRing: View {
    var progress: Double
    var phaseAccent: Color
    var symbol: String
    var fraction: String
    var pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phaseAccent.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 72
                    )
                )
                .frame(width: 136, height: 136)
                .scaleEffect(pulse ? 1.05 : 1)
                .animation(
                    pulse
                    ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true)
                    : .default,
                    value: pulse
                )

            ProgressRing(progress: progress, lineWidth: 5.5, tint: phaseAccent)
                .frame(width: 112, height: 112)

            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(phaseAccent)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulse)
                Text(fraction)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(TaskitTheme.hush)
                    .monospacedDigit()
            }
        }
    }
}
