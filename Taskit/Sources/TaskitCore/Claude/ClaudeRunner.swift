import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Runs one Claude Code invocation to completion.
public protocol ClaudeRunning: Sendable {
    /// Cancelling the calling task terminates the process; the call then
    /// returns whatever output the process produced.
    func run(_ invocation: ClaudeInvocation) async throws -> ProcessOutput
}

public enum ClaudeRunnerError: LocalizedError {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): return "Couldn’t start Claude Code: \(reason)"
        }
    }
}

/// Launches the real `claude` binary with `Process`.
public struct ProcessClaudeRunner: ClaudeRunning {
    /// How long to keep reading after the process exits. Tools Claude started can
    /// inherit its stdout and hold it open; don't wait on them forever.
    public var drainTimeout: TimeInterval = 2
    /// Grace period between SIGTERM and SIGKILL when cancelling.
    public var killTimeout: TimeInterval = 5

    public init() {}

    public func run(_ invocation: ClaudeInvocation) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = invocation.environment
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let handle = ProcessHandle(process, killTimeout: killTimeout)
        let drainTimeout = self.drainTimeout

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
                let out = PipeCollector(outPipe.fileHandleForReading)
                let err = PipeCollector(errPipe.fileHandleForReading)

                process.terminationHandler = { finished in
                    DispatchQueue.global().async {
                        let deadline = DispatchTime.now() + drainTimeout
                        _ = out.waitForEOF(until: deadline)
                        _ = err.waitForEOF(until: deadline)
                        continuation.resume(returning: ProcessOutput(
                            exitCode: finished.terminationStatus,
                            stdout: String(decoding: out.finish(), as: UTF8.self),
                            stderr: String(decoding: err.finish(), as: UTF8.self)
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ClaudeRunnerError.launchFailed(error.localizedDescription))
                    return
                }
                handle.markLaunched()
                out.start()
                err.start()
            }
        } onCancel: {
            handle.terminate()
        }
    }
}

/// Accumulates a pipe's output as it arrives.
private final class PipeCollector: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private let eof = DispatchSemaphore(value: 0)
    private var data = Data()
    private var finished = false

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    /// Reads on a background thread until EOF. Uses POSIX `read`, which returns
    /// whatever is available; `FileHandle.read(upToCount:)` waits for the full
    /// count on macOS, which would strand output behind a pipe held open by a
    /// background tool.
    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let fd = handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                lock.lock()
                if !finished { data.append(contentsOf: buffer[0..<count]) }
                lock.unlock()
            }
            eof.signal()
        }
    }

    func waitForEOF(until deadline: DispatchTime) -> Bool {
        eof.wait(timeout: deadline) == .success
    }

    /// Stops reading and returns everything collected so far.
    func finish() -> Data {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        return data
    }
}

/// Lets the cancellation handler terminate the process safely from any thread.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process
    private let killTimeout: TimeInterval
    private let lock = NSLock()
    private var launched = false
    private var terminateRequested = false

    init(_ process: Process, killTimeout: TimeInterval) {
        self.process = process
        self.killTimeout = killTimeout
    }

    func markLaunched() {
        lock.lock()
        launched = true
        let pending = terminateRequested
        lock.unlock()
        if pending { signalAll() }
    }

    func terminate() {
        lock.lock()
        terminateRequested = true
        let canSignal = launched
        lock.unlock()
        // Signalling a process that never launched raises on macOS; markLaunched handles that case.
        if canSignal { signalAll() }
    }

    private func signalAll() {
        guard process.isRunning else { return }
        send(SIGTERM)
        let process = self.process
        DispatchQueue.global().asyncAfter(deadline: .now() + killTimeout) { [self] in
            if process.isRunning { send(SIGKILL) }
        }
    }

    /// Signals the child's whole process group when it leads one, so tools it
    /// started (shells, test runners) stop too.
    private func send(_ signal: Int32) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        if getpgid(pid) == pid {
            kill(-pid, signal)
        } else {
            kill(pid, signal)
        }
    }
}
