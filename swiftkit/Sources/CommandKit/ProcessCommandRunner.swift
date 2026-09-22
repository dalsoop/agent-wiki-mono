#if os(iOS)
import Foundation

public struct ProcessCommandRunner: CommandRunning {
    public static let defaultWaitDelay: TimeInterval = 0.5
    public init() {}

    public func run(_ spec: CommandSpecification) async -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }

    public func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CommandError.launchFailed("local command execution is unavailable on iOS"))
        }
    }

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        await run(CommandSpecification(launchPath, arguments, timeout: timeout))
    }

    public func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }

    public func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }

    public static func executeWithWaitDelay(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }

    public func executeWithWaitDelay(
        _ spec: CommandSpecification,
        waitDelay: TimeInterval = defaultWaitDelay
    ) async -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }
}
#else
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 외부 프로세스를 실행하고 출력을 수집하거나 라인 스트림으로 방출하는 표준 러너.
///
/// - `setpgid`를 통한 프로세스 그룹 분리로 손자 프로세스 누수 방지
/// - Structured Task Cancellation 지원 (`withTaskCancellationHandler`)
/// - SIGTERM -> (grace 만료 시) SIGKILL 단계적 강제 종료 승격
/// - `ProcessEnvironment`를 통한 표준 PATH 보강 및 SWIFT_EXEC 오염 방지
public struct ProcessCommandRunner: CommandRunning {
    public static let defaultWaitDelay: TimeInterval = 0.5
    public init() {}

    // MARK: - WaitDelay & Direct Execution

    /// Go 스타일 WaitDelay 메커니즘을 적용한 실행 함수.
    ///
    /// 프로세스가 종료된 후 drainGroup.wait(timeout: .now() + waitDelay) 유예 시간을 두고 대기하며,
    /// 시간 초과 시 파일 디스크립터를 강제 close하여 안전하게 반환한다.
    @discardableResult
    public static func executeWithWaitDelay(
        process: Process,
        stdout: Pipe,
        stderr: Pipe,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        ShellCommand.executeWithWaitDelay(
            process: process,
            stdout: stdout,
            stderr: stderr,
            timeout: timeout,
            waitDelay: waitDelay
        )
    }

    @discardableResult
    public static func executeWithWaitDelay(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments
        p.environment = ProcessEnvironment.resolve(environment)
        p.currentDirectoryURL = workingDirectory
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        return executeWithWaitDelay(
            process: p,
            stdout: out,
            stderr: err,
            timeout: timeout,
            waitDelay: waitDelay
        )
    }

    public func executeWithWaitDelay(
        _ spec: CommandSpecification,
        waitDelay: TimeInterval = defaultWaitDelay
    ) async -> CommandResult {
        await run(
            spec.launchPath,
            spec.arguments,
            environment: spec.environment,
            workingDirectory: spec.workingDirectory,
            input: spec.input,
            timeout: spec.timeout,
            waitDelay: spec.waitDelay ?? waitDelay,
            onLine: nil
        )
    }

    // MARK: - CommandRunning Protocol

    public func run(_ spec: CommandSpecification) async -> CommandResult {
        await run(
            spec.launchPath,
            spec.arguments,
            environment: spec.environment,
            workingDirectory: spec.workingDirectory,
            input: spec.input,
            timeout: spec.timeout,
            waitDelay: spec.waitDelay ?? Self.defaultWaitDelay,
            onLine: nil
        )
    }

    public func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.streamProcess(spec, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        await run(launchPath, arguments, environment: nil, workingDirectory: nil, input: nil, timeout: timeout, onLine: nil)
    }

    public func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CommandResult {
        await run(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: nil,
            input: input,
            timeout: timeout,
            onLine: onLine
        )
    }

    public func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CommandResult {
        let terminator = ProcessTerminator()
        let execOptions = ProcessExecutionOptions(timeout: timeout, waitDelay: waitDelay, terminator: terminator)

        return await withTaskCancellationHandler {
            let result = await runProcess(
                launchPath,
                arguments,
                environment: environment,
                workingDirectory: workingDirectory,
                input: input,
                options: execOptions,
                onLine: onLine
            )
            if result.exitCode == 127, Self.isTransientForkError(result.stderr) {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return result
                }
                return await runProcess(
                    launchPath,
                    arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    input: input,
                    options: execOptions,
                    onLine: onLine
                )
            }
            return result
        } onCancel: {
            terminator.cancel()
        }
    }

    private static let transientForkNeedles: [String] = [
        "bad file descriptor",
        "잘못된 파일 서술자",
        "resource temporarily unavailable",
        "일시적으로 사용할 수 없"
    ]

    private static func isTransientForkError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return transientForkNeedles.contains { lower.contains($0) }
    }

    // MARK: - Internal Execution

    private struct ProcessExecutionOptions: Sendable {
        var timeout: TimeInterval?
        var waitDelay: TimeInterval
        var terminator: ProcessTerminator
    }

    private func runProcess(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?,
        input: Data?,
        options: ProcessExecutionOptions,
        onLine: (@Sendable (String) -> Void)?
    ) async -> CommandResult {
        let timeout = options.timeout
        let waitDelay = options.waitDelay
        let terminator = options.terminator
        guard !Task.isCancelled else {
            return CommandResult(stdout: "", stderr: "command cancelled", exitCode: 130)
        }

        let serializedOnLine = makeSerializedLineHandler(onLine)
        let ctx = ProcessContext(
            launchPath: launchPath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            hasInput: input != nil,
            onStdoutLine: serializedOnLine,
            onStderrLine: serializedOnLine
        )

        let startUptime = DispatchTime.now().uptimeNanoseconds
        do {
            try ctx.launchAndAttach(terminator: terminator)
        } catch {
            ctx.abort(hasInput: input != nil)
            let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000.0
            CommandJournal.autoRecordIfEnabled(
                launchPath: launchPath,
                arguments: arguments,
                exitCode: 127,
                durationMs: durationMs,
                workingDirectory: workingDirectory,
                stderr: error.localizedDescription
            )
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 127)
        }

        let exec = await ctx.finishExecution(
            input: input,
            terminator: terminator,
            timeout: timeout,
            waitDelay: waitDelay
        )

        let stderrString = exec.timedOut ? "command timed out after \(Int(timeout ?? 0))s" : String(decoding: exec.stderrData, as: UTF8.self)
        let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000.0
        CommandJournal.autoRecordIfEnabled(
            launchPath: launchPath,
            arguments: arguments,
            exitCode: exec.exitCode,
            durationMs: durationMs,
            workingDirectory: workingDirectory,
            stderr: stderrString
        )
        return CommandResult(
            stdout: String(decoding: exec.stdoutData, as: UTF8.self),
            stderr: stderrString,
            exitCode: exec.exitCode,
            timedOut: exec.timedOut
        )
    }

    private func streamProcess(
        _ spec: CommandSpecification,
        continuation: AsyncThrowingStream<CommandLineOutput, Error>.Continuation
    ) async {
        let terminator = ProcessTerminator()

        await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                continuation.finish(throwing: CancellationError())
                return
            }

            let ctx = ProcessContext(
                launchPath: spec.launchPath,
                arguments: spec.arguments,
                environment: spec.environment,
                workingDirectory: spec.workingDirectory,
                hasInput: spec.input != nil,
                onStdoutLine: { continuation.yield(.stdout($0)) },
                onStderrLine: { continuation.yield(.stderr($0)) }
            )

            let startUptime = DispatchTime.now().uptimeNanoseconds
            do {
                try ctx.launchAndAttach(terminator: terminator)
            } catch {
                ctx.abort(hasInput: spec.input != nil)
                let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000.0
                CommandJournal.autoRecordIfEnabled(
                    launchPath: spec.launchPath,
                    arguments: spec.arguments,
                    exitCode: 127,
                    durationMs: durationMs,
                    workingDirectory: spec.workingDirectory,
                    stderr: error.localizedDescription
                )
                continuation.finish(throwing: CommandError.launchFailed(error.localizedDescription))
                return
            }

            let exec = await ctx.finishExecution(
                input: spec.input,
                terminator: terminator,
                timeout: spec.timeout,
                waitDelay: spec.waitDelay ?? ProcessCommandRunner.defaultWaitDelay
            )

            let stderrString = String(decoding: exec.stderrData, as: UTF8.self)
            let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000.0
            CommandJournal.autoRecordIfEnabled(
                launchPath: spec.launchPath,
                arguments: spec.arguments,
                exitCode: exec.exitCode,
                durationMs: durationMs,
                workingDirectory: spec.workingDirectory,
                stderr: stderrString
            )
            switch (Task.isCancelled, exec.timedOut, exec.exitCode) {
            case (true, _, _):
                continuation.finish(throwing: CancellationError())
            case (false, true, _):
                continuation.finish(throwing: CommandError.timedOut(spec.timeout ?? 0))
            case (false, false, let code) where code != 0:
                continuation.finish(throwing: CommandError.nonZeroExit(exitCode: code, stderr: stderrString))
            default:
                continuation.finish()
            }
        } onCancel: {
            terminator.cancel()
        }
    }

    private func makeSerializedLineHandler(_ onLine: (@Sendable (String) -> Void)?) -> (@Sendable (String) -> Void)? {
        guard let onLine else { return nil }
        let lineQueue = DispatchQueue(label: "CommandKit.ProcessCommandRunner.lines")
        return { @Sendable (line: String) in
            lineQueue.sync {
                onLine(line)
            }
        }
    }
}

// MARK: - Process Context

private struct ProcessContext {
    let process: Process
    let outPipe: Pipe
    let errPipe: Pipe
    let inPipe: Pipe
    let stdoutBuffer: ProcessOutputBuffer
    let stderrBuffer: ProcessOutputBuffer
    let drainGroup: DispatchGroup

    init(
        launchPath: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?,
        hasInput: Bool,
        onStdoutLine: (@Sendable (String) -> Void)? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        proc.environment = ProcessEnvironment.resolve(environment)
        proc.currentDirectoryURL = workingDirectory

        let out = Pipe()
        let err = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = hasInput ? inPipe : FileHandle.nullDevice

        let stdoutBuffer = ProcessOutputBuffer()
        let stderrBuffer = ProcessOutputBuffer()
        let drainGroup = DispatchGroup()

        drain(out.fileHandleForReading, into: stdoutBuffer, group: drainGroup, onLine: onStdoutLine)
        drain(err.fileHandleForReading, into: stderrBuffer, group: drainGroup, onLine: onStderrLine)

        self.process = proc
        self.outPipe = out
        self.errPipe = err
        self.inPipe = inPipe
        self.stdoutBuffer = stdoutBuffer
        self.stderrBuffer = stderrBuffer
        self.drainGroup = drainGroup
    }

    func launchAndAttach(terminator: ProcessTerminator) throws {
        try process.run()
        let pid = process.processIdentifier
        var isGroupLeader = false
        #if canImport(Darwin) || canImport(Glibc)
        if pid > 0 {
            isGroupLeader = (setpgid(pid, pid) == 0)
        }
        #endif
        terminator.attach(process: process, isGroupLeader: isGroupLeader)
    }

    func abort(hasInput: Bool) {
        stdoutBuffer.cancel()
        stderrBuffer.cancel()
        closeFileHandleSilently(outPipe.fileHandleForReading)
        closeFileHandleSilently(errPipe.fileHandleForReading)
        guard hasInput else { return }
        closeFileHandleSilently(inPipe.fileHandleForWriting)
        closeFileHandleSilently(inPipe.fileHandleForReading)
    }

    func finishExecution(
        input: Data?,
        terminator: ProcessTerminator,
        timeout: TimeInterval?,
        waitDelay: TimeInterval = 0.5
    ) async -> ProcessExecutionResult {
        closeFileHandleSilently(outPipe.fileHandleForWriting)
        closeFileHandleSilently(errPipe.fileHandleForWriting)
        if let input {
            writeFileHandleSilently(inPipe.fileHandleForWriting, data: input)
            closeFileHandleSilently(inPipe.fileHandleForWriting)
        }

        let (timedOut, exitCode) = await waitForProcessTermination(process, terminator: terminator, timeout: timeout)
        terminator.cleanup()

        let drained = await waitForDrain(drainGroup, timeout: waitDelay)
        if !drained {
            stdoutBuffer.cancel()
            stderrBuffer.cancel()
            closeFileHandleSilently(outPipe.fileHandleForReading)
            closeFileHandleSilently(errPipe.fileHandleForReading)
            _ = await waitForDrain(drainGroup, timeout: 0.1)
        } else {
            closeFileHandleSilently(outPipe.fileHandleForReading)
            closeFileHandleSilently(errPipe.fileHandleForReading)
        }

        return ProcessExecutionResult(
            timedOut: timedOut,
            exitCode: exitCode,
            stdoutData: stdoutBuffer.snapshot(),
            stderrData: stderrBuffer.snapshot()
        )
    }
}

private struct ProcessExecutionResult: Sendable {
    let timedOut: Bool
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data
}

// MARK: - Output Drainage

private func drainChunk(
    _ count: Int,
    bytes: [UInt8],
    buffer: ProcessOutputBuffer,
    remainder: inout Data,
    onLine: (@Sendable (String) -> Void)?
) -> Bool {
    guard count > 0 else {
        return count == -1 && errno == EINTR
    }
    let chunk = Data(bytes[0..<count])
    guard buffer.append(chunk) else { return false }
    guard let onLine else { return true }
    remainder.append(chunk)
    while let newlineIndex = remainder.firstIndex(of: 0x0A) {
        let lineData = remainder[..<newlineIndex]
        remainder.removeSubrange(...newlineIndex)
        guard let line = String(data: lineData, encoding: .utf8) else { continue }
        onLine(line)
    }
    return true
}

func drain(
    _ handle: FileHandle,
    into buffer: ProcessOutputBuffer,
    group: DispatchGroup,
    onLine: (@Sendable (String) -> Void)? = nil
) {
    let descriptor = handle.fileDescriptor
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        defer { group.leave() }
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        var remainder = Data()
        while !buffer.isCancelled {
            let count = bytes.withUnsafeMutableBytes { rawBuffer in
                read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            guard drainChunk(count, bytes: bytes, buffer: buffer, remainder: &remainder, onLine: onLine) else {
                guard let onLine, !remainder.isEmpty, let line = String(data: remainder, encoding: .utf8) else { return }
                onLine(line)
                return
            }
        }
    }
}

private func waitForDrain(_ group: DispatchGroup, timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
        let waitQueue = DispatchQueue(label: "CommandKit.ProcessCommandRunner.drainWait")
        waitQueue.async {
            let result = group.wait(timeout: .now() + timeout) == .success
            continuation.resume(returning: result)
        }
    }
}

final class ProcessOutputBuffer: Sendable {
    private struct State {
        var data = Data()
        var cancelled = false
    }
    private let state = LockedState(State())

    var isCancelled: Bool {
        state.withLock { $0.cancelled }
    }

    @discardableResult
    func append(_ chunk: Data) -> Bool {
        state.withLock { s in
            guard !s.cancelled else { return false }
            s.data.append(chunk)
            return true
        }
    }

    func cancel() {
        state.withLock { s in
            s.cancelled = true
        }
    }

    func snapshot() -> Data {
        state.withLock { $0.data }
    }
}

private func closeFileHandleSilently(_ handle: FileHandle) {
    do {
        try handle.close()
    } catch {
        return
    }
}

private func writeFileHandleSilently(_ handle: FileHandle, data: Data) {
    do {
        try handle.write(contentsOf: data)
    } catch {
        return
    }
}
#endif
