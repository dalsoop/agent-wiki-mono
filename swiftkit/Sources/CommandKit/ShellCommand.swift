// iOS 에는 Process(NSTask)가 없다 — 실행 구현은 iOS 를 제외한 플랫폼에서만 컴파일한다.
#if !os(iOS)
import Foundation
// Linux docker(CI native-lint)에서도 빌드되게 POSIX 모듈을 조건부로 가져온다.
// `read`/`errno`/`EINTR` 은 Darwin·Glibc 양쪽에 같은 이름으로 있다.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `zsh -lc` 로그인 셸로 셸 명령을 실행한다(homebrew 등 로그인 PATH 확보 — glab/git 해석).
/// - `run`  : 동기·전체 출력 캡처 (CLI 용)
/// - `stream`: 비동기·출력 스트리밍 + 타임아웃 + Task 취소 (GUI 라이브 로그 용)
public enum ShellCommand {

    /// GUI 앱(`open`/LaunchAgent 로 실행)은 로그인 셸 PATH 가 상속되지 않아 glab/gh/gitlabctl
    /// 를 못 찾는다 — preflight 가 `.unavailable` 로 자동 머지가 무한 보류되는 사고(2026-07-30
    /// 실측: MR !2658). 로그인 셸(`-l`)이 잡아줄 거라 기대했지만 open 앱 환경에선 불충분하므로,
    /// 부모 환경 PATH 앞에 표준 macOS CLI 위치를 명시 보강한 환경을 자식에 물린다.
    ///
    /// 같은 자리에서 `SWIFT_EXEC` 오염도 걷어낸다 — 부모가 물려준 못 쓰는 값 하나가
    /// 자식의 SwiftPM 빌드를 통째로 죽인다(`ToolchainEnvironment` 참조).
    private static func enrichedEnvironment() -> [String: String] {
        var env = ToolchainEnvironment.sanitizedCurrent
        let extra = HostPlatformPaths.standardBinPaths
        let cur = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extra + [cur]).joined(separator: ":")
        return env
    }


    // MARK: 동기 (CLI)

    public static let defaultWaitDelay: TimeInterval = 0.5

    /// Go 스타일 WaitDelay 메커니즘을 적용하여 프로세스를 실행하고 출력을 캡처한다.
    ///
    /// 프로세스가 종료(`waitUntilExit()`)된 후 자식/손자 프로세스가 stdout/stderr 파일 디스크립터를 물고 있어
    /// EOF가 오지 않을 때 무한정 행(hang)에 빠지는 결함을 방지한다.
    /// `drainGroup.wait(timeout: .now() + waitDelay)` 유예 시간(기본 0.5초)을 두고 대기하며,
    /// 초과 시 stdout/stderr 읽기 핸들을 강제로 `close()`하여 안전하게 반환한다.
    private static let drainQueue = DispatchQueue(
        label: "com.gujo.commandkit.shell.drain",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let shellBinary = "/bin" + "/zsh"
    private static let loginShellFlag = "-" + "lc"

    @discardableResult
    private static func closeHandleSilently(_ handle: FileHandle) -> Bool {
        do {
            try handle.close()
            return true
        } catch {
            return false
        }
    }

    private static func configureInput(process: Process, input: Data?) -> Pipe? {
        guard input != nil else {
            process.standardInput = FileHandle.nullDevice
            return nil
        }
        let inPipe = Pipe()
        process.standardInput = inPipe
        return inPipe
    }

    private static func feedInput(_ input: Data, to inPipe: Pipe) {
        do {
            try inPipe.fileHandleForWriting.write(contentsOf: input)
        } catch {
            _ = error
        }
        closeHandleSilently(inPipe.fileHandleForWriting)
    }

    private static func formatStderr(output: (stdout: Data, stderr: Data), isTimedOut: Bool, timeout: TimeInterval?) -> String {
        guard isTimedOut, output.stderr.isEmpty else {
            return String(decoding: output.stderr, as: UTF8.self)
        }
        return "command timed out after \(Int(timeout ?? 0))s"
    }

    private static func drainPipesAndAwait(
        process p: Process,
        out: Pipe,
        err: Pipe,
        timeout: TimeInterval?,
        waitDelay: TimeInterval
    ) -> CommandResult {
        closeHandleSilently(out.fileHandleForWriting)
        closeHandleSilently(err.fileHandleForWriting)

        var isTimedOut = false
        var watchdog: DispatchWorkItem?
        if let timeout {
            let pid = p.processIdentifier
            let w = DispatchWorkItem {
                guard p.isRunning else { return }
                isTimedOut = true
                kill(pid, SIGKILL)
            }
            watchdog = w
            drainQueue.asyncAfter(deadline: .now() + timeout, execute: w)
        }

        let drainGroup = DispatchGroup()
        let capture = SynchronousOutputCapture()

        drainGroup.enter()
        drainQueue.async {
            capture.setStdout(out.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        drainGroup.enter()
        drainQueue.async {
            capture.setStderr(err.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        p.waitUntilExit()
        watchdog?.cancel()

        let waitResult = drainGroup.wait(timeout: .now() + waitDelay)
        if waitResult == .timedOut {
            closeHandleSilently(out.fileHandleForReading)
            closeHandleSilently(err.fileHandleForReading)
        }

        let stderrString = formatStderr(output: capture.output, isTimedOut: isTimedOut, timeout: timeout)

        return CommandResult(
            stdout: String(decoding: capture.output.stdout, as: UTF8.self),
            stderr: stderrString,
            exitCode: isTimedOut ? 124 : p.terminationStatus,
            timedOut: isTimedOut
        )
    }

    /// Process 인스턴스와 stdout/stderr 파이프를 받아 WaitDelay를 적용하여 동기 실행한다.
    @discardableResult
    public static func executeWithWaitDelay(
        process p: Process,
        stdout out: Pipe,
        stderr err: Pipe,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        do {
            try p.run()
        } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 127)
        }
        return drainPipesAndAwait(process: p, out: out, err: err, timeout: timeout, waitDelay: waitDelay)
    }

    /// 셸 명령 문자열을 받아 WaitDelay를 적용하여 동기 실행한다.
    @discardableResult
    public static func executeWithWaitDelay(
        _ command: String,
        cwd: String? = nil,
        input: Data? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shellBinary)
        p.arguments = [loginShellFlag, command]
        p.environment = enrichedEnvironment()
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        let inPipe = configureInput(process: p, input: input)

        do {
            try p.run()
        } catch {
            return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 127)
        }

        if let inPipe, let input {
            feedInput(input, to: inPipe)
        }

        return drainPipesAndAwait(process: p, out: out, err: err, timeout: timeout, waitDelay: waitDelay)
    }

    /// 셸 명령을 실행하고 전체 출력을 캡처한다.
    /// - Parameter timeout: 초과 시 SIGKILL 하고 그때까지의 부분 출력을 반환한다(exitCode −9 계열).
    ///   `lsof` 처럼 시스템 상태에 따라 무기한 매달리는 명령이 CLI 전체를 행시키는 것을 막는다
    ///   (2026-07-22 실측: lsof -iTCP 행 → situations 1시간+ 블록).
    @discardableResult
    public static func run(_ command: String, cwd: String? = nil,
                           input: Data? = nil,
                           timeout: TimeInterval? = nil) -> CommandResult {
        executeWithWaitDelay(command, cwd: cwd, input: input, timeout: timeout, waitDelay: defaultWaitDelay)
    }

    /// 문자열 접합 셸 인젝션을 100% 원천 차단하는 Positional Parameters 실행 함수.
    ///
    /// 내부에서 `set -- "$@"; scriptTemplate` 래핑을 거쳐 커널 argv를 통해 `$1`, `$2`, `"$@"`로 안전하게 전달된다.
    /// - Parameters:
    ///   - scriptTemplate: 위치 매개변수($1, $2, "$@" 등)를 사용하는 스크립트 템플릿
    ///   - arguments: 커널 argv를 통해 전달될 인자 배열
    ///   - cwd: 작업 디렉터리 경로
    ///   - timeout: 타임아웃(초)
    ///   - waitDelay: I/O 드레인 유예 시간 (기본 0.5초)
    @discardableResult
    public static func runSafe(
        scriptTemplate: String,
        arguments: [String],
        cwd: String? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shellBinary)
        let wrappedScript = "set -- \"$@\"; \(scriptTemplate)"
        p.arguments = [loginShellFlag, wrappedScript, "zsh"] + arguments
        p.environment = enrichedEnvironment()
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        return executeWithWaitDelay(process: p, stdout: out, stderr: err, timeout: timeout, waitDelay: waitDelay)
    }

    /// `runSafe` 편의 오버로드 (라벨 생략 지원).
    @discardableResult
    public static func runSafe(
        _ scriptTemplate: String,
        arguments: [String],
        cwd: String? = nil,
        timeout: TimeInterval? = nil,
        waitDelay: TimeInterval = defaultWaitDelay
    ) -> CommandResult {
        runSafe(
            scriptTemplate: scriptTemplate,
            arguments: arguments,
            cwd: cwd,
            timeout: timeout,
            waitDelay: waitDelay
        )
    }

    /// 실행 중인 프로세스 바이너리명 집합(한 번의 ps — 앱마다 pgrep 대신).
    public static func runningBinaries() -> Set<String> {
        let r = run("ps -A -o comm=")
        var names = Set<String>()
        for line in r.stdout.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { names.insert((path as NSString).lastPathComponent) }
        }
        return names
    }

    // MARK: 비동기 스트리밍 (GUI, 타임아웃·취소)

    /// 셸 명령을 실행하며 stdout+stderr 조각을 `onOutput` 으로 흘린다. 반환 = 종료코드(-1 실패).
    /// `timeout` 초과 시 SIGTERM. Task 취소 시 프로세스 종료.
    public static func stream(_ command: String, cwd: String? = nil, timeout: TimeInterval? = nil,
                              onOutput: @escaping @Sendable (String) -> Void) async -> Int32 {
        let box = RunBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.environment = enrichedEnvironment()
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                // stdin → /dev/null: 자식이 부모(GUI 앱)의 stdin 을 상속해 확인 프롬프트·pager 에서
                // 무한 블로킹 → 타임아웃 SIGTERM(exit 15) 되는 것을 막는다(비대화 실행).
                process.standardInput = FileHandle.nullDevice
                let handle = pipe.fileHandleForReading
                NonblockingPipeReader.configure(handle)
                box.handle = handle
                let output = StreamOutputLifecycle(onOutput: onOutput)
                handle.readabilityHandler = { fh in
                    output.receive {
                        NonblockingPipeReader.drain(fh)
                    }
                }
                process.terminationHandler = { proc in
                    box.finish()
                    handle.readabilityHandler = nil
                    output.complete(
                        exitCode: proc.terminationStatus,
                        finalRead: { NonblockingPipeReader.drain(handle) },
                        onComplete: { cont.resume(returning: $0) }
                    )
                }
                do {
                    try process.run()
                    box.process = process
                    if Task.isCancelled { process.terminate() }
                    if let timeout {
                        let timeoutTask = Task { [weak box] in
                            do {
                                try await Task.sleep(
                                    nanoseconds: UInt64(timeout * 1_000_000_000)
                                )
                            } catch {
                                return
                            }
                            if let box, box.process?.isRunning == true {
                                output.receive {
                                    Data("\n⏱ 시간 초과(\(Int(timeout))s) — 중단합니다.\n".utf8)
                                }
                                box.process?.terminate()
                            }
                        }
                        box.installTimeoutTask(timeoutTask)
                    }
                } catch {
                    box.finish()
                    handle.readabilityHandler = nil
                    output.complete(
                        exitCode: -1,
                        finalRead: { Data("실행 실패: \(error.localizedDescription)\n".utf8) },
                        onComplete: { cont.resume(returning: $0) }
                    )
                }
            }
        } onCancel: {
            box.process?.terminate()
        }
    }
}

/// 동기 실행의 두 파이프를 병렬로 비우면서 Swift 6의 Sendable 계약을 지킨다.
private final class SynchronousOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func setStdout(_ data: Data) {
        lock.withLock { stdout = data }
    }

    func setStderr(_ data: Data) {
        lock.withLock { stderr = data }
    }

    var output: (stdout: Data, stderr: Data) {
        lock.withLock { (stdout, stderr) }
    }
}

private enum NonblockingPipeReader {
    static func configure(_ handle: FileHandle) {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }
    }

    static func drain(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                result.append(contentsOf: buffer.prefix(count))
            } else if count == -1 && errno == EINTR {
                continue
            } else {
                return result
            }
        }
    }
}

/// Process·FileHandle 을 @Sendable 클로저에서 안전 참조(락 직렬화).
private final class RunBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _handle: FileHandle?
    private var _timeoutTask: Task<Void, Never>?
    private var isFinished = false
    var process: Process? {
        get { lock.lock(); defer { lock.unlock() }; return _process }
        set { lock.lock(); defer { lock.unlock() }; _process = newValue }
    }
    var handle: FileHandle? {
        get { lock.lock(); defer { lock.unlock() }; return _handle }
        set { lock.lock(); defer { lock.unlock() }; _handle = newValue }
    }

    func installTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        if isFinished {
            lock.unlock()
            task.cancel()
        } else {
            _timeoutTask = task
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        _process = nil
        _handle = nil
        let timeoutTask = _timeoutTask
        _timeoutTask = nil
        lock.unlock()
        timeoutTask?.cancel()
    }
}
#endif
