import AppKit
import SwiftUI

/// The few colors the panel needs beyond system ones. Everything else follows
/// the system appearance and accent color.
enum Theme {
    static let statusFill = Color.primary.opacity(0.05)
    static let rowHighlight = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.12)

    static let waitingText = dynamic(
        light: NSColor(srgbRed: 0.48, green: 0.26, blue: 0.0, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.74, blue: 0.40, alpha: 1)
    )
    static let waitingFill = dynamic(
        light: NSColor(srgbRed: 0.984, green: 0.945, blue: 0.882, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.20, alpha: 0.14)
    )
    static let waitingBar = dynamic(
        light: NSColor(srgbRed: 0.70, green: 0.42, blue: 0.0, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.66, blue: 0.25, alpha: 1)
    )
    static let failure = Color(nsColor: .systemRed)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// Small borderless icon button used in the header and rows.
struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A ScrollView that is only as tall as its content, up to `maxHeight`.
struct FittedScrollView<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
