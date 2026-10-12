import SwiftUI
import TaskitCore

/// First run, inside the panel: find Claude Code, check sign-in, pick a folder.
@MainActor
struct SetupView: View {
    let app: AppModel

    private var engine: RelayEngine { app.engine }
    private var ready: Bool { app.claudeURL != nil && engine.settings.projectURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Taskit")
                    .font(.system(size: 17, weight: .bold))
                Text("Taskit sends your queued prompts to Claude Code one at a time, and waits out usage limits for you.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                claudeRow
                Divider()
                signInRow
                Divider()
                folderRow
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )

            Toggle(isOn: Binding(
                get: { engine.settings.autoMode },
                set: { value in app.update { $0.autoMode = value } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run without stopping to ask")
                        .font(.system(size: 13, weight: .medium))
                    Text("Claude Code uses auto mode, so it can edit files and run commands in this folder while you are away. Risky actions are still blocked.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Quit") { app.quit() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open queue") {
                    app.update { $0.setupComplete = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onAppear { app.refreshClaude() }
    }

    // MARK: - Rows

    private var claudeRow: some View {
        SetupRow(
            done: app.claudeURL != nil,
            title: app.claudeURL != nil ? "Claude Code is installed" : "Install Claude Code",
            detail: app.claudeURL?.path ?? "Not found on this Mac",
            monospacedDetail: app.claudeURL != nil
        ) {
            if app.claudeURL == nil {
                HStack(spacing: 6) {
                    Link("Install…", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                    Button("Locate…") { app.chooseClaudeBinary() }
                    Button("Recheck") { app.refreshClaude() }
                }
                .controlSize(.small)
            }
        }
    }

    private var signInRow: some View {
        let detail: String
        let done: Bool
        switch app.signIn {
        case .unknown:
            done = false
            detail = "Uses your Pro or Max plan. Check sends one tiny prompt."
        case .checking:
            done = false
            detail = "Checking…"
        case .signedIn:
            done = true
            detail = "Uses your Pro or Max plan. No API key needed."
        case .notSignedIn:
            done = false
            detail = "Not signed in. Sign in opens Terminal and runs claude."
        case .error(let message):
            done = false
            detail = message
        }
        return SetupRow(
            done: done,
            title: done ? "Signed in to Claude" : "Sign in to Claude",
            detail: detail,
            monospacedDetail: false
        ) {
            HStack(spacing: 6) {
                if app.signIn == .notSignedIn {
                    Button("Sign in…") { app.openInTerminal(sessionId: nil) }
                }
                if app.signIn != .signedIn {
                    Button("Check") {
                        Task { await app.checkSignIn() }
                    }
                    .disabled(app.signIn == .checking || app.claudeURL == nil)
                }
            }
            .controlSize(.small)
        }
    }

    private var folderRow: some View {
        SetupRow(
            done: engine.settings.projectURL != nil,
            title: "Project folder",
            detail: engine.settings.projectURL == nil ? "Where Claude Code should work" : engine.settings.projectDisplayPath,
            monospacedDetail: engine.settings.projectURL != nil
        ) {
            Button(engine.settings.projectURL == nil ? "Choose…" : "Change…") {
                app.chooseProjectFolder()
            }
            .controlSize(.small)
        }
    }
}

@MainActor
private struct SetupRow<Accessory: View>: View {
    let done: Bool
    let title: String
    let detail: String
    let monospacedDetail: Bool
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(monospacedDetail ? .system(size: 11, design: .monospaced) : .system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
