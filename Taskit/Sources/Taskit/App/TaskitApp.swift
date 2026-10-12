import SwiftUI
import TaskitCore

@main
struct TaskitApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(app: app)
        } label: {
            MenuBarLabel(engine: app.engine)
        }
        .menuBarExtraStyle(.window)

        Window("Taskit Settings", id: "settings") {
            SettingsView(app: app)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Icon plus the shortest useful text: "3", "2/5", "2:14", "Paused".
@MainActor
struct MenuBarLabel: View {
    let engine: RelayEngine

    var body: some View {
        if engine.phase == .waiting {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                label(at: context.date)
            }
        } else {
            label(at: Date())
        }
    }

    private func label(at now: Date) -> some View {
        let text = Self.text(for: engine, now: now)
        return HStack(spacing: 4) {
            Image(systemName: Self.symbol(for: engine.phase))
            if !text.isEmpty {
                Text(text).monospacedDigit()
            }
        }
    }

    static func symbol(for phase: Phase) -> String {
        switch phase {
        case .empty, .idle: return "list.bullet"
        case .running: return "play.circle"
        case .waiting: return "hourglass"
        case .paused: return "pause.circle"
        case .done: return "checkmark.circle"
        }
    }

    static func text(for engine: RelayEngine, now: Date) -> String {
        let finished = engine.doneCount + engine.failedCount
        switch engine.phase {
        case .empty: return ""
        case .idle: return "\(engine.pendingCount)"
        case .running, .done: return "\(finished)/\(engine.items.count)"
        case .waiting:
            guard let limit = engine.limit else { return "" }
            return DurationFormat.menuCountdown(limit.resetsAt.timeIntervalSince(now))
        case .paused: return "Paused"
        }
    }
}
