import Foundation

/// Options for `InteractiveProcess.start`.
public struct InteractiveProcessOptions: Sendable {
    public var environment: [String: String]?
    public var workingDirectory: URL?
    /// Signal the child's whole process group so `terminate` also reaches grandchildren.
    /// On macOS `Process` starts the child as its own group leader. Elsewhere the group is set
    /// right after launch, so a grandchild forked within that first instant can stay outside it.
    public var newProcessGroup: Bool
    /// Deliver stderr through the stdout callback as one merged stream.
    public var mergeStderrIntoStdout: Bool

    public init(
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        newProcessGroup: Bool = false,
        mergeStderrIntoStdout: Bool = false
    ) {
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.newProcessGroup = newProcessGroup
        self.mergeStderrIntoStdout = mergeStderrIntoStdout
    }
}

public enum InteractiveProcessError: Error, Equatable {
    /// `write` was called after `closeStdin()`.
    case stdinClosed
}

/// Splits streamed output chunks into lines. An unfinished line longer than `limit` bytes is
/// dropped so a child that never prints a newline cannot grow memory without bound.
public final class LineAccumulator: Sendable {
    private let pending = LockedState(Data())
    private let limit: Int

    public init(limit: Int = 1_048_576) {
        self.limit = limit
    }

    /// Appends a chunk and returns every completed line without its trailing newline.
    public func append(_ chunk: Data) -> [String] {
        pending.withLock { buffer -> [String] in
            buffer.append(chunk)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            if buffer.count > limit {
                buffer.removeAll(keepingCapacity: false)
            }
            return lines
        }
    }

    /// Returns the unfinished last line (if any) and clears it. Call after the stream ends.
    public func flush() -> String? {
        pending.withLock { buffer -> String? in
            guard !buffer.isEmpty else { return nil }
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: false)
            return line
        }
    }
}

#if os(iOS)
/// iOS stub. `Process` does not exist on iOS.
public final class InteractiveProcess: Sendable {
    public let processIdentifier: Int32 = -1
    public var isRunning: Bool { false }
    public var exitStatus: Int32? { nil }

    public static func start(
        _ launchPath: String,
        _ arguments: [String],
        options: InteractiveProcessOptions = InteractiveProcessOptions(),
        onStdout: @escaping @Sendable (Data) -> Void,
        onStderr: @escaping @Sendable (Data) -> Void = { _ in },
        onExit: @escaping @Sendable (Int32) -> Void = { _ in }
    ) throws -> InteractiveProcess {
        throw CocoaError(.featureUnsupported)
    }

    public func write(_ data: Data) throws {
        throw CocoaError(.featureUnsupported)
    }

    public func write(_ data: Data, timeout: TimeInterval) -> Bool { false }
    public func closeStdin() {}
    public func terminate(grace: TimeInterval = 1) {}
    public func waitUntilExit(timeout: TimeInterval?) -> Int32? { nil }
}
#else
/// Interactive sibling of `RunningProcess`: a long-lived child whose stdin stays open and whose
/// stdout/stderr arrive as chunks while it runs. Nothing is accumulated here, so memory stays flat
/// for chatty children (MCP servers, agent CLIs, remote build streams).
public final class InteractiveProcess: Sendable {
    private struct State {
        var process: Process?
        var stdin: FileHandle?
        var exitStatus: Int32?
    }

    public let processIdentifier: Int32
    private let isGroupLeader: Bool
    private let state: LockedState<State>
    private let exited: DispatchGroup

    private init(processIdentifier: Int32, isGroupLeader: Bool, state: LockedState<State>, exited: DispatchGroup) {
        self.processIdentifier = processIdentifier
        self.isGroupLeader = isGroupLeader
        self.state = state
        self.exited = exited
    }

    public var isRunning: Bool { state.withLock { $0.exitStatus == nil } }
    public var exitStatus: Int32? { state.withLock { $0.exitStatus } }

    /// Starts the child and returns immediately. Callbacks run on background queues.
    /// `onExit` fires after the remaining output was delivered (bounded to 2 seconds).
    public static func start(
        _ launchPath: String,
        _ arguments: [String],
        options: InteractiveProcessOptions = InteractiveProcessOptions(),
        onStdout: @escaping @Sendable (Data) -> Void,
        onStderr: @escaping @Sendable (Data) -> Void = { _ in },
        onExit: @escaping @Sendable (Int32) -> Void = { _ in }
    ) throws -> InteractiveProcess {
        let process = makeProcess(launchPath, arguments, options: options)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = options.mergeStderrIntoStdout ? stdoutPipe : Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        disableSigpipe(on: stdinPipe.fileHandleForWriting)

        let initial = State(process: process, stdin: stdinPipe.fileHandleForWriting, exitStatus: nil)
        let state = LockedState(initial)
        let readers = DispatchGroup()
        let exited = DispatchGroup()
        attach(stdoutPipe.fileHandleForReading, readers: readers, deliver: onStdout)
        if !options.mergeStderrIntoStdout {
            attach(stderrPipe.fileHandleForReading, readers: readers, deliver: onStderr)
        }
        exited.enter()
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            _ = readers.wait(timeout: .now() + 2)
            state.withLock { current in
                current.exitStatus = status
                current.process = nil
            }
            onExit(status)
            exited.leave()
        }
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            exited.leave()
            throw error
        }
        let pid = process.processIdentifier
        let leader = options.newProcessGroup && becomeGroupLeader(pid)
        return InteractiveProcess(processIdentifier: pid, isGroupLeader: leader, state: state, exited: exited)
    }

    /// Writes to the child's stdin. Throws `InteractiveProcessError.stdinClosed` after `closeStdin()`
    /// and rethrows the write error (EPIPE) once the child has gone. Blocks while the 64KB pipe
    /// buffer is full; use `write(_:timeout:)` when the child may stop reading.
    public func write(_ data: Data) throws {
        guard let handle = state.withLock({ $0.stdin }) else {
            throw InteractiveProcessError.stdinClosed
        }
        try handle.write(contentsOf: data)
    }

    /// Like `write(_:)` but stops waiting after `timeout` seconds and returns false.
    public func write(_ data: Data, timeout: TimeInterval) -> Bool {
        let group = DispatchGroup()
        let succeeded = LockedState(false)
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { group.leave() }
            do {
                try write(data)
                succeeded.withLock { $0 = true }
            } catch {
                succeeded.withLock { $0 = false }
            }
        }
        guard group.wait(timeout: .now() + timeout) == .success else { return false }
        return succeeded.withLock { $0 }
    }

    /// Closes stdin so the child sees end-of-file. Safe to call more than once.
    public func closeStdin() {
        let handle = state.withLock { current -> FileHandle? in
            let handle = current.stdin
            current.stdin = nil
            return handle
        }
        handle?.closeFile()
    }

    /// Sends SIGTERM (to the whole group when started with `newProcessGroup`) and escalates to
    /// SIGKILL when the child is still alive after `grace` seconds.
    public func terminate(grace: TimeInterval = 1) {
        guard isRunning else { return }
        send(SIGTERM)
        guard exited.wait(timeout: .now() + grace) == .timedOut else { return }
        send(SIGKILL)
    }

    /// Waits for exit and returns the status, or nil on timeout. A nil timeout waits forever.
    public func waitUntilExit(timeout: TimeInterval?) -> Int32? {
        if let timeout {
            guard exited.wait(timeout: .now() + timeout) == .success else { return nil }
        } else {
            exited.wait()
        }
        return exitStatus
    }

    private func send(_ signalNumber: Int32) {
        if isGroupLeader {
            SafeProcessRunner.killProcessGroup(pgid: processIdentifier, signal: signalNumber)
        } else {
            kill(processIdentifier, signalNumber)
        }
    }

    private static func makeProcess(
        _ launchPath: String,
        _ arguments: [String],
        options: InteractiveProcessOptions
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment = options.environment {
            process.environment = environment
        }
        if let directory = options.workingDirectory {
            process.currentDirectoryURL = directory
        }
        return process
    }

    private static func attach(
        _ handle: FileHandle,
        readers: DispatchGroup,
        deliver: @escaping @Sendable (Data) -> Void
    ) {
        readers.enter()
        handle.readabilityHandler = { readable in
            let chunk = readable.availableData
            guard !chunk.isEmpty else {
                readable.readabilityHandler = nil
                readers.leave()
                return
            }
            deliver(chunk)
        }
    }

    /// macOS `Process` already launches the child as the leader of its own group, and a
    /// `setpgid` after exec then fails with EACCES (measured 2026-09-24). Check the group first
    /// and only create it where the platform did not.
    private static func becomeGroupLeader(_ pid: Int32) -> Bool {
        if getpgid(pid) == pid { return true }
        return setpgid(pid, pid) == 0
    }

    private static func disableSigpipe(on handle: FileHandle) {
        #if canImport(Darwin)
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        #endif
    }
}
#endif
