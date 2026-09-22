import Foundation

/// 아주 얇은 프로세스 러너. swiftkit `CommandKit` 대신 이걸 쓰는 이유는 이 Core 가
/// **PATH CLI 에 링크**되기 때문이다 — Foundation 밖으로 나가면 dual-entry 가 위험해진다.
public enum Shell {
    /// 표준출력을 문자열로. 종료코드가 0 이 아니거나 실행 실패·시간초과면 nil.
    ///
    /// **타임아웃이 실제로 걸려야 한다.** 초판은 `readDataToEndOfFile()` 로 먼저 블로킹한 뒤
    /// 데드라인을 검사해서, 자식이 안 끝나면 타임아웃 코드에 도달조차 못 했다 — 설치본 GUI 에서
    /// `git rev-parse` 가 90초 넘게 매달려 팩 미리보기가 영영 스피너로 남았다(2026-07-27 실측).
    /// 그래서 읽기를 별도 큐로 보내고 세마포어로 기다린다.
    public static func capture(_ argv: [String], cwd: String? = nil, timeout: TimeInterval = 10) -> String? {
        guard let first = argv.first else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: first)
        p.arguments = Array(argv.dropFirst())
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        // stdin 을 물려주면 자식이 입력을 기다리며 멈출 수 있다.
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        // 파이프를 계속 비워야 한다 — 64KB 버퍼가 차면 자식이 write 에서 멈춘다.
        let box = OutputBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(pipe.fileHandleForReading.readDataToEndOfFile())
            done.signal()
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut, p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: box.get(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }

    /// 읽기 스레드와 호출 스레드가 주고받는 작은 상자.
    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
