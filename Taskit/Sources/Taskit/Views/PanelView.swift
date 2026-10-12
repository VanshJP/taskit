import AppKit
import SwiftUI
import TaskitCore

/// The menu bar panel: header, one status block, the queue, and the composer.
@MainActor
struct PanelView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var expanded: UUID?

    private var engine: RelayEngine { app.engine }

    var body: some View {
        VStack(spacing: 0) {
            if engine.settings.setupComplete {
                header
                StatusBlock(app: app)
                    .padding(.horizontal, 10)
                queue
                Divider()
                ComposerView(app: app)
            } else {
                SetupView(app: app)
            }
        }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 2) {
            Button {
                app.chooseProjectFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(engine.settings.projectName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(engine.settings.projectDisplayPath)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change project folder")
            .accessibilityLabel("Change project folder")

            Spacer(minLength: 8)

            if showsPauseButton {
                if engine.runState == .running {
                    IconButton(systemName: "pause.fill", label: "Pause after current prompt") {
                        engine.pause()
                    }
                } else {
                    IconButton(systemName: "play.fill", label: "Resume queue") {
                        engine.start()
                    }
                }
            }

            Menu {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                if engine.hasFinished {
                    Button("Clear finished") { engine.clearFinished() }
                }
                Divider()
                Button("Quit Taskit") { app.quit() }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var showsPauseButton: Bool {
        switch engine.phase {
        case .running, .waiting: return true
        case .paused: return engine.hasPending
        case .empty, .idle, .done: return false
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Queue

    @ViewBuilder
    private var queue: some View {
        if engine.items.isEmpty {
            Text("Type a prompt below, or paste a list.\nOne prompt per line, or separate longer ones with a blank line.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 16)
        } else {
            let positions = pendingPositions
            FittedScrollView(maxHeight: 340) {
                LazyVStack(spacing: 1) {
                    ForEach(engine.items) { item in
                        QueueRowView(
                            app: app,
                            item: item,
                            position: positions[item.id],
                            isUpNext: positions[item.id] == 1 && engine.runningItem == nil && engine.phase == .idle,
                            isExpanded: expanded == item.id,
                            toggleExpanded: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    expanded = expanded == item.id ? nil : item.id
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
        }
    }

    /// 1-based position of each pending prompt, for the numbered circles.
    private var pendingPositions: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var position = 0
        for item in engine.items where item.isPending {
            position += 1
            result[item.id] = position
        }
        return result
    }
}
