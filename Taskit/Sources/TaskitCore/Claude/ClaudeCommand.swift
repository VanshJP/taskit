import Foundation

/// One `claude` process launch.
public struct ClaudeInvocation: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL
    public var environment: [String: String]

    public init(executable: URL, arguments: [String], workingDirectory: URL, environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public enum ClaudeCommand {
    /// Arguments for a headless run: `claude -p … --output-format json`.
    public static func arguments(
        prompt: String,
        resumeSessionId: String?,
        autoMode: Bool,
        model: String
    ) -> [String] {
        var args = ["--output-format", "json"]
        if let resumeSessionId, !resumeSessionId.isEmpty {
            args += ["--resume", resumeSessionId]
        }
        if autoMode {
            args += ["--permission-mode", "auto"]
        }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            args += ["--model", model]
        }
        args.append("-p")
        // A prompt that starts with "-" would otherwise be read as a flag.
        if prompt.hasPrefix("-") { args.append("--") }
        args.append(prompt)
        return args
    }

    /// Environment for the child process. GUI apps don't get the shell's PATH,
    /// so the login-shell PATH is merged in (npm installs need `node` on it).
    /// `ANTHROPIC_API_KEY` is dropped: headless Claude Code prefers it over the
    /// subscription login, which would silently bill the API instead.
    public static func environment(
        base: [String: String],
        loginShellPath: String?
    ) -> [String: String] {
        var env = base
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        let home = base["HOME"] ?? NSHomeDirectory()
        let extra = [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        var parts: [String] = []
        for chunk in [loginShellPath, base["PATH"]].compactMap({ $0 }) {
            parts += chunk.split(separator: ":").map(String.init)
        }
        parts += extra
        var seen = Set<String>()
        env["PATH"] = parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return env
    }
}

/// Finds the `claude` binary the way a terminal would.
public enum ClaudeLocator {
    public static func candidates(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude"
        ]
    }

    /// `override` first, then well-known install locations, then any `claude` on `path`.
    public static func locate(
        override: String,
        home: String = NSHomeDirectory(),
        path: String?,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        let trimmed = (override.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if !trimmed.isEmpty {
            return isExecutable(trimmed) ? URL(fileURLWithPath: trimmed) : nil
        }
        var options = candidates(home: home)
        options += (path ?? "").split(separator: ":").map { "\($0)/claude" }
        return options.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }

    /// PATH as the user's login shell sets it, e.g. from ~/.zprofile.
    public static func loginShellPath(shell: String? = ProcessInfo.processInfo.environment["SHELL"]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell ?? "/bin/zsh")
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
