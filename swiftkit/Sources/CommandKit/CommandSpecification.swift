import Foundation

/// 외부 프로세스 실행 명령에 대한 불변 명세.
public struct CommandSpecification: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// 실행할 바이너리 경로 또는 이름.
    public var launchPath: String
    /// 명령행 인자 목록.
    public var arguments: [String]
    /// 환경 변수 덮어쓰기 (nil인 경우 ProcessEnvironment 기본 규칙 적용).
    public var environment: [String: String]?
    /// 작업 디렉터리 URL.
    public var workingDirectory: URL?
    /// 표준 입력으로 전달할 데이터.
    public var input: Data?
    /// 타임아웃(초). 초과 시 프로세스 그룹에 단계적 종료 시그널이 전달된다.
    public var timeout: TimeInterval?
    /// 프로세스 종료 후 I/O 드레인 대기 유예 시간 (기본 0.5초).
    public var waitDelay: TimeInterval?

    /// 실행 경로와 인자로 명령 명세를 초기화한다.
    public init(
        _ launchPath: String,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval? = nil
    ) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.input = input
        self.timeout = timeout
        self.waitDelay = waitDelay
    }

    /// 라벨 기반 초기화 편의 이니셜라이저.
    public init(
        launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval? = nil
    ) {
        self.init(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            timeout: timeout,
            waitDelay: waitDelay
        )
    }

    /// 문자열 경로 작업 디렉터리를 받는 초기화 편의 이니셜라이저.
    public init(
        launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectoryPath: String?,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval? = nil
    ) {
        self.init(
            launchPath,
            arguments,
            environment: environment,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            input: input,
            timeout: timeout,
            waitDelay: waitDelay
        )
    }

    /// executable 별칭 프로퍼티.
    public var executable: String {
        get { launchPath }
        set { launchPath = newValue }
    }

    /// workingDirectoryURL 별칭 프로퍼티.
    public var workingDirectoryURL: URL? {
        get { workingDirectory }
        set { workingDirectory = newValue }
    }

    /// workingDirectoryPath 별칭 프로퍼티.
    public var workingDirectoryPath: String? {
        get { workingDirectory?.path }
        set { workingDirectory = newValue.map { URL(fileURLWithPath: $0) } }
    }

    // MARK: Fluent Mutators

    public func withArguments(_ args: [String]) -> CommandSpecification {
        var copy = self
        copy.arguments = args
        return copy
    }

    public func withEnvironment(_ env: [String: String]?) -> CommandSpecification {
        var copy = self
        copy.environment = env
        return copy
    }

    public func withWorkingDirectory(_ dir: URL?) -> CommandSpecification {
        var copy = self
        copy.workingDirectory = dir
        return copy
    }

    public func withWorkingDirectory(path: String?) -> CommandSpecification {
        var copy = self
        copy.workingDirectory = path.map { URL(fileURLWithPath: $0) }
        return copy
    }

    public func withInput(_ data: Data?) -> CommandSpecification {
        var copy = self
        copy.input = data
        return copy
    }

    public func withTimeout(_ t: TimeInterval?) -> CommandSpecification {
        var copy = self
        copy.timeout = t
        return copy
    }

    public func withWaitDelay(_ d: TimeInterval?) -> CommandSpecification {
        var copy = self
        copy.waitDelay = d
        return copy
    }

    public var description: String {
        if arguments.isEmpty {
            return launchPath
        }
        return "\(launchPath) \(arguments.joined(separator: " "))"
    }
}

/// 스트리밍 명령 실행 시 단일 라인 단위 출력 이벤트.
public enum CommandLineOutput: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    case stdout(String)
    case stderr(String)

    /// 스트림 구분 열거형.
    public enum Stream: String, Sendable, Equatable, Hashable, Codable {
        case stdout
        case stderr
    }

    /// 출력 텍스트 내용.
    public var text: String {
        switch self {
        case .stdout(let text), .stderr(let text):
            return text
        }
    }

    /// line 별칭 프로퍼티.
    public var line: String { text }

    /// 표준 에러 스트림 여부.
    public var isStderr: Bool {
        switch self {
        case .stderr: return true
        case .stdout: return false
        }
    }

    /// 표준 출력 스트림 여부.
    public var isStdout: Bool {
        !isStderr
    }

    /// 소속 스트림 유형.
    public var stream: Stream {
        switch self {
        case .stdout: return .stdout
        case .stderr: return .stderr
        }
    }

    public init(text: String, stream: Stream = .stdout) {
        switch stream {
        case .stdout: self = .stdout(text)
        case .stderr: self = .stderr(text)
        }
    }

    public init(_ text: String, stream: Stream = .stdout) {
        self.init(text: text, stream: stream)
    }

    public var description: String { text }
}

/// 외부 명령 실행 시 발생할 수 있는 표준 에러.
public enum CommandError: Error, LocalizedError, Sendable, Equatable {
    case launchFailed(String)
    case timedOut(TimeInterval)
    case nonZeroExit(exitCode: Int32, stderr: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Command launch failed: \(message)"
        case .timedOut(let interval):
            return "Command timed out after \(interval)s"
        case .nonZeroExit(let exitCode, let stderr):
            return "Command exited with code \(exitCode): \(stderr)"
        case .cancelled:
            return "Command execution was cancelled"
        }
    }
}
