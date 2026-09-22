import Foundation
import ArgumentParser
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ArgumentParser 명령의 인프로세스 실행 결과.
public struct CLITestResult: Sendable, Equatable {
    /// 명령 실행 종료 코드.
    public let exitCode: Int32
    /// 표준 출력 문자열.
    public let stdout: String
    /// 표준 에러 문자열.
    public let stderr: String
    /// 명령 실행 경과 시간(초 단위).
    public let duration: TimeInterval

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        duration: TimeInterval
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }

    /// 성공 여부 (exitCode == 0).
    public var isSuccess: Bool {
        exitCode == 0
    }

    /// 표준 출력과 표준 에러를 결합한 문자열.
    public var combinedOutput: String {
        stdout + stderr
    }

    /// 좌우 공백 및 개행이 제거된 표준 출력.
    public var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 좌우 공백 및 개행이 제거된 표준 에러.
    public var trimmedStderr: String {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `ArgumentParser` 기반 CLI 명령을 프로세스 분기 없이 메모리 내에서 안전하게 테스트하는 하네스.
///
/// 표준 출력(`stdout`)과 표준 에러(`stderr`)를 캡처하며,
/// `ArgumentParser`의 도움말/버전/유효성 검사 에러 및 파싱 결과를 포착합니다.
public enum CLITestHarness {
    private static let redirectLock = NSLock()

    /// `ParsableCommand`를 인프로세스로 동기 실행하고 출력과 결과를 캡처합니다.
    ///
    /// - Parameters:
    ///   - commandType: 테스트할 `ParsableCommand` 메타타입.
    ///   - arguments: 명령에 전달할 인자 배열 (프로그램명 제외).
    ///   - environment: 명령 실행 동안 임시로 적용할 환경변수 (선택사항).
    /// - Returns: `CLITestResult`
    public static func run<T: ParsableCommand>(
        _ commandType: T.Type,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> CLITestResult {
        if let environment {
            let overrides = environment.mapValues { Optional($0) }
            return TestEnvironment.withTestEnvironment(overrides) {
                executeCapturing(commandType, arguments: arguments) { command in
                    var cmd = command
                    try cmd.run()
                }
            }
        } else {
            return executeCapturing(commandType, arguments: arguments) { command in
                var cmd = command
                try cmd.run()
            }
        }
    }

    /// `AsyncParsableCommand` 또는 비동기 실행이 필요한 명령을 인프로세스로 비동기 실행하고 캡처합니다.
    ///
    /// - Parameters:
    ///   - commandType: 테스트할 `ParsableCommand` 메타타입.
    ///   - arguments: 명령에 전달할 인자 배열.
    ///   - environment: 명령 실행 동안 임시로 적용할 환경변수 (선택사항).
    /// - Returns: `CLITestResult`
    public static func runAsync<T: ParsableCommand>(
        _ commandType: T.Type,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async -> CLITestResult {
        if let environment {
            let overrides = environment.mapValues { Optional($0) }
            return await TestEnvironment.withTestEnvironment(overrides) {
                await executeCapturingAsync(commandType, arguments: arguments) { command in
                    if var asyncCmd = command as? AsyncParsableCommand {
                        try await asyncCmd.run()
                    } else {
                        var cmd = command
                        try cmd.run()
                    }
                }
            }
        } else {
            return await executeCapturingAsync(commandType, arguments: arguments) { command in
                if var asyncCmd = command as? AsyncParsableCommand {
                    try await asyncCmd.run()
                } else {
                    var cmd = command
                    try cmd.run()
                }
            }
        }
    }

    // MARK: - Internal Capture Machinery

    private static func executeCapturing<T: ParsableCommand>(
        _ commandType: T.Type,
        arguments: [String],
        invoker: (T) throws -> Void
    ) -> CLITestResult {
        redirectLock.withLock {
            let start = DispatchTime.now().uptimeNanoseconds
            let session = OutputCaptureSession()
            session.start()

            var exitCode: Int32 = 0
            var extraStdout = ""
            var extraStderr = ""

            do {
                let parsed = try T.parseAsRoot(arguments)
                guard let typedCommand = parsed as? T else {
                    throw CleanExit.helpRequest()
                }
                try invoker(typedCommand)
                exitCode = 0
            } catch {
                exitCode = T.exitCode(for: error).rawValue
                let message = T.fullMessage(for: error)
                if !message.isEmpty {
                    if exitCode == 0 {
                        extraStdout = message
                    } else {
                        extraStderr = message
                    }
                }
            }

            let captured = session.stop()
            let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0

            let finalStdout = joinOutput(captured.stdout, extra: extraStdout)
            let finalStderr = joinOutput(captured.stderr, extra: extraStderr)

            return CLITestResult(
                exitCode: exitCode,
                stdout: finalStdout,
                stderr: finalStderr,
                duration: duration
            )
        }
    }

    private actor AsyncCaptureCoordinator {
        static let shared = AsyncCaptureCoordinator()

        func execute<T: ParsableCommand>(
            _ commandType: T.Type,
            arguments: [String],
            invoker: @Sendable (T) async throws -> Void
        ) async -> CLITestResult {
            let start = DispatchTime.now().uptimeNanoseconds
            let session = OutputCaptureSession()
            session.start()

            var exitCode: Int32 = 0
            var extraStdout = ""
            var extraStderr = ""

            do {
                let parsed = try T.parseAsRoot(arguments)
                guard let typedCommand = parsed as? T else {
                    throw CleanExit.helpRequest()
                }
                try await invoker(typedCommand)
                exitCode = 0
            } catch {
                exitCode = T.exitCode(for: error).rawValue
                let message = T.fullMessage(for: error)
                if !message.isEmpty {
                    if exitCode == 0 {
                        extraStdout = message
                    } else {
                        extraStderr = message
                    }
                }
            }

            let captured = session.stop()
            let end = DispatchTime.now().uptimeNanoseconds
            let duration = Double(end - start) / 1_000_000_000.0

            let finalStdout = extraStdout.isEmpty ? captured.stdout : (captured.stdout + extraStdout)
            let finalStderr = extraStderr.isEmpty ? captured.stderr : (captured.stderr + extraStderr)

            return CLITestResult(
                exitCode: exitCode,
                stdout: finalStdout,
                stderr: finalStderr,
                duration: duration
            )
        }
    }

    private static func executeCapturingAsync<T: ParsableCommand>(
        _ commandType: T.Type,
        arguments: [String],
        invoker: @escaping @Sendable (T) async throws -> Void
    ) async -> CLITestResult {
        await AsyncCaptureCoordinator.shared.execute(commandType, arguments: arguments, invoker: invoker)
    }

    private static func joinOutput(_ captured: String, extra: String) -> String {
        guard !extra.isEmpty else { return captured }
        if captured.isEmpty { return extra }
        if captured.hasSuffix("\n") {
            return captured + extra
        } else {
            return captured + "\n" + extra
        }
    }
}

// MARK: - OutputCaptureSession

private final class OutputCaptureSession {
    private let stdoutCollector = OutputCollector()
    private let stderrCollector = OutputCollector()

    private var originalStdoutFd: Int32 = -1
    private var originalStderrFd: Int32 = -1

    private var outPipe: Pipe?
    private var errPipe: Pipe?

    func start() {
        fflush(stdout)
        fflush(stderr)

        originalStdoutFd = dup(STDOUT_FILENO)
        originalStderrFd = dup(STDERR_FILENO)

        let out = Pipe()
        let err = Pipe()
        self.outPipe = out
        self.errPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak stdoutCollector] handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stdoutCollector?.append(chunk)
            }
        }

        err.fileHandleForReading.readabilityHandler = { [weak stderrCollector] handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stderrCollector?.append(chunk)
            }
        }

        dup2(out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(err.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    }

    func stop() -> (stdout: String, stderr: String) {
        fflush(stdout)
        fflush(stderr)

        if originalStdoutFd >= 0 {
            dup2(originalStdoutFd, STDOUT_FILENO)
            close(originalStdoutFd)
            originalStdoutFd = -1
        }
        if originalStderrFd >= 0 {
            dup2(originalStderrFd, STDERR_FILENO)
            close(originalStderrFd)
            originalStderrFd = -1
        }

        if let out = outPipe {
            try? out.fileHandleForWriting.close()
            out.fileHandleForReading.readabilityHandler = nil
            let remaining = out.fileHandleForReading.readDataToEndOfFile()
            stdoutCollector.append(remaining)
            try? out.fileHandleForReading.close()
            self.outPipe = nil
        }

        if let err = errPipe {
            try? err.fileHandleForWriting.close()
            err.fileHandleForReading.readabilityHandler = nil
            let remaining = err.fileHandleForReading.readDataToEndOfFile()
            stderrCollector.append(remaining)
            try? err.fileHandleForReading.close()
            self.errPipe = nil
        }

        return (stdoutCollector.string(), stderrCollector.string())
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
