import Foundation

/// codex 등 외부 프로세스를 stdin 주입·작업디렉터리 지정과 함께 실행한다.
///
/// CommandKit 의 `CommandRunning` 은 stdin 파이프를 지원하지 않는다. 이미지 생성 파이프라인은
/// `cat prompt | codex exec --cd DIR -i canon.png -` 처럼 프롬프트를 **stdin 으로** 넣어야 하므로
/// (`-i` 가 위치 프롬프트 인자를 삼킨다) GenKit 전용 러너를 둔다.
public protocol ProcessRunning: Sendable {
    func run(
        _ launchPath: String,
        _ arguments: [String],
        stdin: String?,
        cwd: String?,
        timeout: TimeInterval?
    ) async -> ProcessOutcome
}

/// 프로세스 실행 결과.
public struct ProcessOutcome: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var ok: Bool { exitCode == 0 }

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// `Process` 기반 기본 구현. stdout/stderr 를 동시에 드레인하고, stdin 을 주입한다.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        _ launchPath: String,
        _ arguments: [String],
        stdin: String?,
        cwd: String?,
        timeout: TimeInterval?
    ) async -> ProcessOutcome {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        if let cwd { proc.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        let inPipe: Pipe? = stdin != nil ? Pipe() : nil
        if let inPipe { proc.standardInput = inPipe }

        do {
            try proc.run()
        } catch {
            return ProcessOutcome(stdout: "", stderr: error.localizedDescription, exitCode: 127)
        }

        if let inPipe, let stdin {
            let handle = inPipe.fileHandleForWriting
            handle.write(Data(stdin.utf8))
            try? handle.close()
        }

        let timeoutTask: Task<Void, Never>? = timeout.map { seconds in
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if proc.isRunning { proc.terminate() }
            }
        }

        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        async let outBytes = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let errBytes = Task.detached { errHandle.readDataToEndOfFile() }.value
        let stdout = String(data: await outBytes, encoding: .utf8) ?? ""
        let stderr = String(data: await errBytes, encoding: .utf8) ?? ""
        proc.waitUntilExit()
        timeoutTask?.cancel()
        return ProcessOutcome(stdout: stdout, stderr: stderr, exitCode: proc.terminationStatus)
    }
}
