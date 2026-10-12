import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 5
    var tint: Color = Color.white.opacity(0.75)

    var body: some View {
        let clamped = min(1, max(0, progress))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    Color.white.opacity(0.7),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
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
                .fill(Color.white.opacity(0.03))
                .frame(width: 128, height: 128)

            ProgressRing(progress: progress, lineWidth: 4.5, tint: phaseAccent)
                .frame(width: 108, height: 108)

            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(fraction)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(TaskitTheme.hush)
                    .monospacedDigit()
            }
        }
        // No looping pulse — quiet utility.
        .opacity(pulse ? 1 : 1)
    }
}
