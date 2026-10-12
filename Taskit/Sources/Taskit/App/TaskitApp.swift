import SwiftUI
import TaskitCore

@main
struct TaskitApp: App {
    @State private var engine = RelayEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(engine: engine)
        } label: {
            // Timeline only while cooling — idle/active labels stay static (zero timer cost).
            if engine.session.phase == .cooling {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    menuLabel(at: context.date)
                }
            } else {
                menuLabel(at: .now)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }

    @ViewBuilder
    private func menuLabel(at date: Date) -> some View {
        Label {
            Text(engine.menuBarLabel(at: date))
        } icon: {
            Image(systemName: menuSymbol)
                .symbolRenderingMode(.hierarchical)
        }
        .help(engine.statusMessage)
    }

    private var menuSymbol: String {
        if engine.isPaused { return "pause.circle" }
        switch engine.session.phase {
        case .cooling: return "hourglass"
        case .ready: return "sparkles"
        case .active: return "guidepost.fill"
        case .idle: return "moon.stars"
        }
    }
}
