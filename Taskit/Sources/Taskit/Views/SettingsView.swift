import SwiftUI
import TaskitCore

/// The settings window: project, behaviour while running, notifications, Claude Code.
@MainActor
struct SettingsView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    private var engine: RelayEngine { app.engine }

    var body: some View {
        Form {
            Section("Project") {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(engine.settings.projectURL == nil ? "None" : engine.settings.projectDisplayPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button("Change…") { app.chooseProjectFolder() }
                    }
                }
                Picker("Conversation", selection: binding(\.conversationMode)) {
                    ForEach(ConversationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(engine.settings.conversationMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While running") {
                Toggle(isOn: binding(\.autoMode)) {
                    Text("Run without stopping to ask")
                    Text("Claude Code auto mode. Risky actions are still blocked.")
                }
                Toggle(isOn: binding(\.keepAwake)) {
                    Text("Keep the Mac awake")
                    Text("Only while prompts are running or waiting. The lid must stay open.")
                }
                Toggle(isOn: binding(\.launchAtLogin)) {
                    Text("Open at login")
                    Text("So an overnight queue survives a restart.")
                }
            }

            Section("Notify me when") {
                Toggle("Each prompt finishes", isOn: binding(\.notifyEachPrompt))
                Toggle("A usage limit pauses the queue", isOn: binding(\.notifyLimit))
                Toggle("The whole queue is done", isOn: binding(\.notifyQueueDone))
            }

            Section("Claude Code") {
                LabeledContent("Location") {
                    HStack(spacing: 8) {
                        Text(app.claudeURL?.path ?? "Not found")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(app.claudeURL == nil ? Theme.failure : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { app.chooseClaudeBinary() }
                        if !engine.settings.claudePath.isEmpty {
                            Button("Auto-detect") { app.update { $0.claudePath = "" } }
                        }
                    }
                }
                TextField("Model", text: binding(\.model), prompt: Text("Claude Code default"))
                LabeledContent("Sign-in") {
                    HStack(spacing: 8) {
                        Text(signInText)
                            .foregroundStyle(.secondary)
                        Button("Check") { Task { await app.checkSignIn() } }
                            .disabled(app.signIn == .checking || app.claudeURL == nil)
                    }
                }
            }

            Section {
                HStack {
                    Button("Quit Taskit") { app.quit() }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear { app.refreshClaude() }
    }

    private var signInText: String {
        switch app.signIn {
        case .unknown: return "Not checked"
        case .checking: return "Checking…"
        case .signedIn: return "Signed in"
        case .notSignedIn: return "Not signed in"
        case .error: return "Couldn’t check"
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RelaySettings, Value>) -> Binding<Value> {
        Binding(
            get: { engine.settings[keyPath: keyPath] },
            set: { value in app.update { $0[keyPath: keyPath] = value } }
        )
    }
}
