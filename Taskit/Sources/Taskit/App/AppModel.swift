import AppKit
import Observation
import ServiceManagement
import TaskitCore
import UserNotifications

enum SignInStatus: Equatable {
    case unknown
    case checking
    case signedIn
    case notSignedIn
    case error(String)
}

/// App-side glue around the engine: notifications, keep-awake, Terminal, pickers.
@MainActor
@Observable
final class AppModel {
    let engine: RelayEngine
    /// Composer text, kept here so it survives the panel closing.
    var draft = ""
    private(set) var claudeURL: URL? = nil
    private(set) var signIn: SignInStatus = .unknown

    @ObservationIgnored private let environment = ClaudeEnvironment()
    @ObservationIgnored private var keepAwakeToken: NSObjectProtocol?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let environment = self.environment
        engine = RelayEngine(store: FileQueueStore(), environment: { environment.current() })
        engine.onEvent = { [weak self] event in self?.handle(event) }

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.systemDidWake() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.shutdown() }
        })

        Notifier.requestAuthorization()
        Task {
            // The login-shell PATH can take a moment; resume the queue once it's known
            // so npm/nvm installs of `claude` are found.
            await environment.warmUp()
            refreshClaude()
            engine.activate()
        }
    }

    // MARK: - Settings

    func update(_ mutate: (inout RelaySettings) -> Void) {
        let before = engine.settings
        engine.updateSettings(mutate)
        let after = engine.settings
        if after.claudePath != before.claudePath { refreshClaude() }
        if after.keepAwake != before.keepAwake { applyKeepAwake(engine.isActive) }
        if after.launchAtLogin != before.launchAtLogin { LoginItem.set(after.launchAtLogin) }
    }

    func refreshClaude() {
        claudeURL = RelayEngine.defaultLocate(engine.settings, environment.current())
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Claude Code should work in."
        if let current = engine.settings.projectURL { panel.directoryURL = current }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update { $0.projectPath = url.path }
    }

    func chooseClaudeBinary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.prompt = "Use"
        panel.message = "Choose the claude executable."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update { $0.claudePath = url.path }
    }

    // MARK: - Terminal

    /// Opens Terminal in the project folder running `claude`, resuming a session if given.
    func openInTerminal(sessionId: String?) {
        let directory = engine.settings.projectURL ?? FileManager.default.homeDirectoryForCurrentUser
        let env = environment.current()
        let claude = claudeURL?.path ?? "claude"
        var command = "cd \(shellQuote(directory.path)) && exec \(shellQuote(claude))"
        if let sessionId, !sessionId.isEmpty {
            command += " --resume \(shellQuote(sessionId))"
        }
        let script = """
        #!/bin/sh
        export PATH=\(shellQuote(env["PATH"] ?? "/usr/bin:/bin"))
        \(command)

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskit-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Sign-in check

    /// Sends one tiny prompt to confirm Claude Code is signed in.
    func checkSignIn() async {
        guard let claudeURL else {
            signIn = .error("Claude Code wasn’t found.")
            return
        }
        signIn = .checking
        var args = ClaudeCommand.arguments(
            prompt: "Reply with the single word OK.",
            resumeSessionId: nil,
            autoMode: false,
            model: engine.settings.model
        )
        args.insert(contentsOf: ["--max-turns", "1"], at: 0)
        let invocation = ClaudeInvocation(
            executable: claudeURL,
            arguments: args,
            workingDirectory: engine.settings.projectURL ?? FileManager.default.homeDirectoryForCurrentUser,
            environment: environment.current()
        )
        do {
            let output = try await ProcessClaudeRunner().run(invocation)
            switch ClaudeOutputParser.parse(output, now: Date()) {
            case .success, .limited:
                signIn = .signedIn
            case .failed(_, _, .notSignedIn):
                signIn = .notSignedIn
            case let .failed(message, _, _):
                signIn = .error(message)
            case .cancelled:
                signIn = .unknown
            }
        } catch {
            signIn = .error(error.localizedDescription)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func quit() {
        engine.shutdown()
        NSApp.terminate(nil)
    }

    // MARK: - Events

    private func handle(_ event: RelayEvent) {
        let settings = engine.settings
        switch event {
        case .promptStarted, .limitCleared:
            break
        case .promptFinished(let item):
            if settings.notifyEachPrompt { Notifier.post("Prompt finished", item.title) }
        case .promptFailed(let item):
            if settings.notifyEachPrompt { Notifier.post("Prompt failed", item.title) }
        case .limitHit(let limit):
            if settings.notifyLimit {
                Notifier.post("Usage limit reached", "Taskit will continue at \(Format.time(limit.resetsAt)).")
            }
        case let .queueFinished(done, failed):
            if settings.notifyQueueDone {
                let body = failed == 0 ? "All \(done) prompts are done." : "\(done) done, \(failed) failed."
                Notifier.post("Queue finished", body)
            }
        case .activityChanged(let active):
            applyKeepAwake(active)
        }
    }

    private func applyKeepAwake(_ active: Bool) {
        let wanted = active && engine.settings.keepAwake
        if wanted, keepAwakeToken == nil {
            keepAwakeToken = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                reason: "Taskit is running your Claude Code queue"
            )
        } else if !wanted, let token = keepAwakeToken {
            ProcessInfo.processInfo.endActivity(token)
            keepAwakeToken = nil
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Child-process environment with the user's login-shell PATH, computed once.
final class ClaudeEnvironment: @unchecked Sendable {
    private let lock = NSLock()
    private var loginPath: String?

    func warmUp() async {
        let path = await Task.detached(priority: .utility) { ClaudeLocator.loginShellPath() }.value
        lock.lock()
        loginPath = path
        lock.unlock()
    }

    func current() -> [String: String] {
        lock.lock()
        let path = loginPath
        lock.unlock()
        return ClaudeCommand.environment(base: ProcessInfo.processInfo.environment, loginShellPath: path)
    }
}

enum Notifier {
    /// UserNotifications crashes outside an app bundle (e.g. `swift run`).
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

enum LoginItem {
    /// Needs a signed .app; silently does nothing from `swift run`.
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Not available for unsigned builds.
        }
    }
}

enum Format {
    static func time(_ date: Date, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        if Calendar.current.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        }
        return formatter.string(from: date)
    }
}
