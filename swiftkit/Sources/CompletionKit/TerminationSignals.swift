import Dispatch
import Foundation

/// SIGTERM/SIGINT 로 죽을 때도 정리 훅을 돌린다 — 자식 프로세스(llama-server 등)를 거두기 위해.
///
/// **왜 필요한가.** `applicationWillTerminate` 는 Cmd+Q · Apple Event quit · 로그아웃에서만
/// 돈다. `killall`, 스크립트 종료, 개발 중 재기동 같은 **raw SIGTERM 은 기본 핸들러가 곧장
/// 프로세스를 exit** 시켜 훅이 돌 기회가 없다. 그러면 자식이 launchd 에 입양돼 고아(PPID=1)로
/// 남고, 로컬 LLM 서버의 경우 모델 RAM 수 GB 를 무기한 점유한다.
///
/// 실측 근거: keyboard-coding-typer·keyboard-typer 양쪽에서 고아 llama-server 2건(1.8GB +
/// 2.9GB)이 1시간 넘게 살아있는 것을 확인했다. applicationWillTerminate 만으로는 부족하다.
///
/// **사용.** 앱 기동 시 1회 `install`. 훅은 동기로 끝나야 한다 — 신호 처리 중엔 실행 시간이
/// 짧아야 하고, 여기서 exit(0) 하므로 비동기 정리는 완료되지 못한다.
@MainActor
public enum TerminationSignals {
    /// 소스를 살려두기 위한 보관소(해제되면 신호 감시가 끊긴다).
    private static var sources: [DispatchSourceSignal] = []
    private static var installed = false

    /// SIGTERM·SIGINT 수신 시 cleanup 을 돌리고 정상 종료한다. 중복 호출은 무시.
    public static func install(_ cleanup: @escaping @MainActor () -> Void) {
        guard !installed else { return }
        installed = true
        for sig in [SIGTERM, SIGINT] {
            // 기본 동작(즉시 종료)을 끄지 않으면 아래 소스가 돌기 전에 프로세스가 사라진다.
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                MainActor.assumeIsolated { cleanup() }
                exit(0)
            }
            src.resume()
            sources.append(src)
        }
    }

    /// 테스트용 — 설치 여부.
    public static var isInstalled: Bool { installed }
}
