import SwiftUI
import TaskitCore

struct SettingsView: View {
    @Bindable var engine: RelayEngine
    @State private var apiKeyDraft = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    connectionSection
                    goalSection
                    relaySection
                    sessionSection
                    notifySection
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 560)
        .background { TaskitTheme.atmosphere }
        .onAppear {
            apiKeyDraft = engine.apiKeyPresent ? "••••••••••••" : ""
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taskit")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var connectionSection: some View {
        settingsCard("Cursor") {
            LabeledContent("API key") {
                SecureField("crsr_… or key from Dashboard", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit(saveKey)
            }
            HStack {
                Text(engine.apiKeyPresent ? "Key saved in Keychain" : "Required for Cloud Agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save key", action: saveKey)
            }
            TextField("Repository URL", text: binding(\.repositoryURL))
                .textFieldStyle(.roundedBorder)
            TextField("Branch", text: binding(\.startingRef))
                .textFieldStyle(.roundedBorder)
            TextField("Model ID (optional)", text: binding(\.modelId))
                .textFieldStyle(.roundedBorder)
            Toggle("Auto-create pull request", isOn: binding(\.autoCreatePR))
        }
    }

    private var goalSection: some View {
        settingsCard("Overarching goal") {
            Text("Prepended to every prompt so each handoff stays aligned.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: binding(\.overarchingGoal))
                .font(.body)
                .frame(minHeight: 88)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Toggle("Prepend overarching goal", isOn: binding(\.prependOverarchingGoal))
        }
    }

    private var relaySection: some View {
        settingsCard("Relay") {
            Picker("Dispatch mode", selection: binding(\.dispatchMode)) {
                ForEach(DispatchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(engine.settings.dispatchMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Continue when a run finishes", isOn: binding(\.autoContinueOnFinish))
            Toggle("Resume when the limit window clears", isOn: binding(\.autoResumeOnLimitReset))
        }
    }

    private var sessionSection: some View {
        settingsCard("Session window") {
            HStack {
                Text("Default cool-down")
                Spacer()
                Text("\(engine.settings.sessionWindowHours, specifier: "%.1f") h")
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .rounded))
            }
            Slider(value: binding(\.sessionWindowHours), in: 0.5...12, step: 0.5)
            Toggle("Open at login", isOn: binding(\.launchAtLogin))
                .onChange(of: engine.settings.launchAtLogin) { _, value in
                    LaunchAtLogin.setEnabled(value)
                }
        }
    }

    private var notifySection: some View {
        settingsCard("Notifications") {
            Toggle("When a prompt is sent", isOn: binding(\.notifyOnDispatch))
            Toggle("When a goal completes", isOn: binding(\.notifyOnComplete))
            Toggle("When a limit is hit", isOn: binding(\.notifyOnLimit))
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                content()
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { engine.settings[keyPath: keyPath] },
            set: { newValue in
                engine.updateSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "••••••••••••" else { return }
        engine.updateAPIKey(trimmed)
        apiKeyDraft = engine.apiKeyPresent ? "••••••••••••" : ""
    }
}
