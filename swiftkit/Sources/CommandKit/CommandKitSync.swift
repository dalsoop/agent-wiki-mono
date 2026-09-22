// iOS 에는 Process(NSTask)가 없다 — 실행 구현은 iOS 를 제외한 플랫폼에서만 컴파일하고,
// iOS 에는 항상 실패를 돌려주는 스텁을 둔다(ProcessCommandRunner 와 같은 가드).
#if os(iOS)
import Foundation

/// 동기 호출 경로. 앱마다 같은 래퍼를 복사하지 말고 이 타입을 쓴다.
public enum CommandKitSync {
    public static func run(_ spec: CommandSpecification) -> CommandResult {
        CommandResult(stdout: "", stderr: "local command execution is unavailable on iOS", exitCode: 127)
    }

    public static func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = 30,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> CommandResult {
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

/// 동기 호출 경로 — 협력 스레드 풀을 거치지 않고 Process 를 직접 굴린다.
///
/// 옛 구현은 비동기 러너를 `Task.detached` + semaphore 로 감쌌는데, detached 작업도
/// 스케줄되려면 협력 풀 스레드가 필요하다. 호출자(Swift Testing 테스트 본문 등)가
/// 같은 풀을 semaphore 대기로 채우면 detached 작업은 영원히 돌지 못한다 — 2026-08-22
/// 실측: suite 전체가 교착하고 자식 프로세스는 0개, 풀 스레드는 전부 semaphore_wait.
/// 동기 실행은 각 호출이 자기 자식의 종료로 스레드를 반납하므로 진행이 보장된다.
/// 앱마다 같은 래퍼를 복사하지 말고 이 타입을 쓴다.
public enum CommandKitSync {
    public static func run(_ spec: CommandSpecification) -> CommandResult {
        run(
            spec.launchPath,
            spec.arguments,
            environment: spec.environment,
            workingDirectory: spec.workingDirectory,
            input: spec.input,
            timeout: spec.timeout
        )
    }

    public static func run(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = 30,
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> CommandResult {
        #if DEBUG
        if Thread.isMainThread {
            let message = "[CommandKitSync] Warning: Synchronous process execution on Main Thread (\(launchPath) \(arguments.joined(separator: " "))). This causes UI beachball/hang.\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
        #endif
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        if let environment {
            proc.environment = environment
        }
        if let workingDirectory {
            proc.currentDirectoryURL = workingDirectory
        }
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        let inPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            inPipe = pipe
            proc.standardInput = pipe
        } else {
            inPipe = nil
            proc.standardInput = FileHandle.nullDevice
        }

        let stdoutBuffer = ProcessOutputBuffer()
        let stderrBuffer = ProcessOutputBuffer()
        let drainGroup = DispatchGroup()
        drain(out.fileHandleForReading, into: stdoutBuffer, group: drainGroup, onLine: onLine)
        drain(err.fileHandleForReading, into: stderrBuffer, group: drainGroup, onLine: onLine)

        defer {
            safeClose(out.fileHandleForReading)
            safeClose(out.fileHandleForWriting)
            safeClose(err.fileHandleForReading)
            safeClose(err.fileHandleForWriting)
            if let inPipe {
                safeClose(inPipe.fileHandleForReading)
                safeClose(inPipe.fileHandleForWriting)
            }
        }

        let startUptime = DispatchTime.now().uptimeNanoseconds
        do {
            try proc.run()
        } catch {
            stdoutBuffer.cancel()
            stderrBuffer.cancel()
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
        safeClose(out.fileHandleForWriting)
        safeClose(err.fileHandleForWriting)

        writeInput(pipe: inPipe, data: input)

        let (exitCode, timedOut) = waitForExit(proc: proc, timeout: timeout, isCancelled: isCancelled)

        if drainGroup.wait(timeout: .now() + 0.2) != .success {
            stdoutBuffer.cancel()
            stderrBuffer.cancel()
            _ = drainGroup.wait(timeout: .now() + 0.2)
        }
        safeClose(out.fileHandleForReading)
        safeClose(err.fileHandleForReading)
        let stderrString = timedOut ? "command timed out after \(Int(timeout ?? 0))s" : String(decoding: stderrBuffer.snapshot(), as: UTF8.self)
        let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startUptime) / 1_000_000.0
        CommandJournal.autoRecordIfEnabled(
            launchPath: launchPath,
            arguments: arguments,
            exitCode: exitCode,
            durationMs: durationMs,
            workingDirectory: workingDirectory,
            stderr: stderrString
        )
        return CommandResult(
            stdout: String(decoding: stdoutBuffer.snapshot(), as: UTF8.self),
            stderr: stderrString,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }

    private static func safeClose(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            #if canImport(Darwin)
            let fd = handle.fileDescriptor
            if fd >= 0 {
                _ = close(fd)
            }
            #elseif canImport(Glibc)
            let fd = handle.fileDescriptor
            if fd >= 0 {
                _ = Glibc.close(fd)
            }
            #endif
        }
    }

    private static func writeInput(pipe: Pipe?, data: Data?) {
        guard let pipe, let data else { return }
        safeClose(pipe.fileHandleForReading)
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            #if canImport(Darwin)
            let fd = pipe.fileHandleForWriting.fileDescriptor
            if fd >= 0 {
                _ = close(fd)
            }
            #elseif canImport(Glibc)
            let fd = pipe.fileHandleForWriting.fileDescriptor
            if fd >= 0 {
                _ = Glibc.close(fd)
            }
            #endif
        }
        safeClose(pipe.fileHandleForWriting)
    }

    private static func waitForExit(
        proc: Process,
        timeout: TimeInterval?,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> (exitCode: Int32, timedOut: Bool) {
        guard proc.isRunning else {
            return (proc.terminationStatus, false)
        }

        let sema = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in
            sema.signal()
        }

        if !proc.isRunning {
            proc.terminationHandler = nil
            return (proc.terminationStatus, false)
        }

        if let isCancelled {
            while proc.isRunning {
                if isCancelled() {
                    proc.terminate()
                    let killResult = sema.wait(timeout: .now() + 1.0)
                    if killResult == .timedOut, proc.isRunning {
                        #if canImport(Darwin) || canImport(Glibc)
                        kill(proc.processIdentifier, SIGKILL)
                        #endif
                        sema.wait()
                    }
                    proc.terminationHandler = nil
                    return (130, false)
                }
                if sema.wait(timeout: .now() + 0.1) == .success {
                    break
                }
            }
            proc.terminationHandler = nil
            return (proc.terminationStatus, false)
        }

        var timedOut = false
        if let timeout, timeout > 0 {
            let result = sema.wait(timeout: .now() + timeout)
            if result == .timedOut {
                timedOut = true
                if proc.isRunning {
                    proc.terminate()
                    let killResult = sema.wait(timeout: .now() + 1.0)
                    if killResult == .timedOut, proc.isRunning {
                        #if canImport(Darwin) || canImport(Glibc)
                        kill(proc.processIdentifier, SIGKILL)
                        #endif
                        sema.wait()
                    }
                }
            }
        } else {
            sema.wait()
        }

        proc.terminationHandler = nil
        let exitCode = timedOut ? 124 : proc.terminationStatus
        return (exitCode, timedOut)
    }
}
#endif
