// iOS 에는 Process(NSTask)가 없다 — 실행 구현은 iOS 를 제외한 플랫폼에서만 컴파일한다.
#if os(iOS)
import Foundation

/// iOS 스텁. Process 가 없다.
public final class RunningProcess: Sendable {
    public let processIdentifier: Int32 = -1
    public var isRunning: Bool { false }
    public var terminationStatus: Int32 { 0 }
    public func terminate() {}
}

extension CommandKitSync {
    public static func spawn(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> RunningProcess {
        throw CocoaError(.featureUnsupported)
    }
}
#else
import Foundation

/// `CommandKitSync.spawn` 이 돌려주는 살아있는 자식 프로세스 핸들.
///
/// `run`/`ShellCommand.run` 은 종료까지 동기 대기하므로, "실행 중인 pid 를 다른 로직이
/// 회수(kill)하는지" 를 검증해야 하는 호출자(예: 워커 회수 테스트)에는 못 쓴다. 이 타입은
/// 그 좁은 용도만 위해 존재한다 — 일반 실행은 여전히 `run` 을 쓴다.
///
/// pid 는 즉시 노출하되, 자식 종료는 내부 스레드가 `waitUntilExit` 로 회수해 좀비를
/// 남기지 않는다. `Process` 자체는 밖으로 노출하지 않는다 — 노출하면 결국 호출자가
/// 다시 raw `Process` 를 붙들게 되어 이 타입을 만든 이유가 사라진다.
public final class RunningProcess: Sendable {
    // `Process` 자체는 Apple 문서상 스레드 안전을 보장하지 않지만, 이 핸들이 노출하는
    // 연산(pid 읽기·isRunning 폴링·terminate)은 각각 독립 시스템 콜이라 겹쳐 불려도
    // 데이터 레이스가 아니다 — 그 이상의 동시 호출(예: 두 스레드가 동시에 terminate)까지
    // 안전을 보장하진 않는다.
    private let process: Process

    fileprivate init(process: Process) {
        self.process = process
    }

    public var processIdentifier: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }
    public var terminationStatus: Int32 { process.terminationStatus }

    /// SIGTERM. 강제 종료가 필요하면 `kill(-processIdentifier, SIGKILL)` 을 직접 호출한다
    /// (프로세스 그룹째 죽이려면 `setpgid` 로 자기 그룹을 만든 프로세스여야 한다).
    public func terminate() { process.terminate() }
}

extension CommandKitSync {
    /// 자식을 띄우고 종료를 기다리지 않고 즉시 반환한다. pid 생명주기 자체가 테스트
    /// 대상일 때만 쓴다(예: 죽거나 살아있는 워커를 회수하는 로직 검증) — 일반 실행은 `run`.
    public static func spawn(
        _ launchPath: String,
        _ arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        standardOutput: Any? = nil,
        standardError: Any? = nil
    ) throws -> RunningProcess {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        if let environment { proc.environment = environment }
        if let workingDirectory { proc.currentDirectoryURL = workingDirectory }
        proc.standardOutput = standardOutput ?? Pipe()
        proc.standardError = standardError ?? Pipe()
        proc.standardInput = FileHandle.nullDevice
        try proc.run()
        // 호출자가 pid 만 들고 있고 Process 인스턴스는 버리므로, 여기서 회수하지 않으면
        // 자식이 좀비로 남는다.
        Thread { proc.waitUntilExit() }.start()
        return RunningProcess(process: proc)
    }
}
#endif
