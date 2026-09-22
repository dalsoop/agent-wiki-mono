// iOS 에는 Process(NSTask)가 없다 — 실행 구현은 iOS 를 제외한 플랫폼에서만 컴파일한다.
#if !os(iOS)
import Foundation

/// 외부 CLI(ssh·glab·git·kubectl·curl)를 `zsh -lc` 로그인 셸로 비동기 실행하는 얇은 러너.
///
/// server-infra-stages·gujo-infra-stages 의 어댑터층이 복붙해 쓰던 러너의 정본. 셸 문자열 하나를
/// 받아 전체 출력을 캡처하고 timeout(기본 30s) 초과 시 SIGTERM 한다. stdout/stderr 를 **동시에**
/// 드레인한 뒤 exit 를 기다린다 — waitUntilExit 를 먼저 부르고 나중에 읽으면 출력이 64KB 파이프
/// 버퍼를 넘길 때 child 가 write 에서 블록되고 parent 가 exit 를 기다려 데드락(2.5MB argo json 실사고).
public struct ShellRunner: Sendable {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public init() {}

    public func run(_ command: String, timeout: TimeInterval = 30) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = ["-lc", command]
                let out = Pipe(); let err = Pipe()
                p.standardOutput = out; p.standardError = err
                do { try p.run() } catch {
                    cont.resume(returning: .init(exitCode: -1, stdout: "", stderr: "\(error)"))
                    return
                }
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
                let outH = out.fileHandleForReading, errH = err.fileHandleForReading
                // 백그라운드 큐에서 채운 Data 를 캡처 var 로 직접 변형하면 Swift 6 동시성 검사가
                // 데이터 레이스로 막는다(macOS 는 눈감지만 Linux 는 컴파일 거부). g.wait() 가
                // happens-before 배리어를 주므로 실제 레이스는 없다 — 참조형 박스로 감싸
                // @unchecked Sendable 로 검사만 통과시킨다(의미·데드락 회피 로직 불변).
                final class DataBox: @unchecked Sendable { var data = Data() }
                let soBox = DataBox(), seBox = DataBox()
                let g = DispatchGroup()
                g.enter(); DispatchQueue.global().async { soBox.data = outH.readDataToEndOfFile(); g.leave() }
                g.enter(); DispatchQueue.global().async { seBox.data = errH.readDataToEndOfFile(); g.leave() }
                p.waitUntilExit()
                g.wait()
                let so = String(data: soBox.data, encoding: .utf8) ?? ""
                let se = String(data: seBox.data, encoding: .utf8) ?? ""
                cont.resume(returning: .init(exitCode: p.terminationStatus, stdout: so, stderr: se))
            }
        }
    }
}
#endif
