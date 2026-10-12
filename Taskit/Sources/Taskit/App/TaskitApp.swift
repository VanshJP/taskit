import SwiftUI
import TaskitCore

@main
struct TaskitApp: App {
    @State private var engine = RelayEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(engine: engine)
        } label: {
            Label {
                Text("Taskit")
            } icon: {
                Image(systemName: menuSymbol)
                    .symbolRenderingMode(.hierarchical)
            }
            .help(engine.statusMessage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }

    private var menuSymbol: String {
        switch engine.session.phase {
        case .cooling: return "hourglass"
        case .ready: return "sparkles"
        case .active: return "guidepost.fill"
        case .idle: return "moon.stars"
        }
    }
}
