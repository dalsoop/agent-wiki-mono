import Foundation

/// **종료 코드는 함대의 공용 언어다.** 매직넘버로 흩어지면 뜻이 갈린다.
///
/// 조회하는 쪽(`agent-fleet-query`)은 코드만 보고 네 갈래로 나눈다. 그래서 각 앱이
/// 같은 뜻에 같은 숫자를 써야 한다 — 안 그러면 "고쳐야 할 목록" 이 거짓이 된다.
///
/// 실측(2026-08-05): 함대에 `status` 를 물었더니 "문제 14건" 이 나왔는데,
/// 갈라 보니 **실제 코드 결함은 1건**이었다. 나머지는 인자 부족(3)·미설정(3)·
/// 안 고치기로 한 것(3)·못 닿음 등이 전부 `exit 1` 로 뭉쳐 있던 것이다.
///
/// 지금 `exit(64)` 를 쓰는 앱이 223개인데 전부 숫자를 직접 적는다. 뜻을 이름으로
/// 고정해 두면 새 앱이 규약을 물려받고, 조회하는 쪽도 계약을 믿을 수 있다.
///
/// ## 네 갈래
///
///     0   정상
///     1   발견        고쳐야 한다. 이 앱/대상에 실제 문제가 있다
///     64  질문이 틀림  사용법 오류 — 인자를 빠뜨렸거나 모르는 옵션(EX_USAGE)
///     69  설정 안 됨  자격증명·연결·전제가 없다. 설정하면 사라진다(EX_UNAVAILABLE)
///
/// 64·69 는 `sysexits.h` 의 표준값이라 셸·다른 도구와도 뜻이 맞는다.
public enum CLIExit {
    /// 정상.
    public static let ok: Int32 = 0

    /// **발견** — 실제 문제. 사람이 고쳐야 한다.
    ///
    /// "무언가 걸렸다" 는 뜻이지 "프로그램이 죽었다" 가 아니다. 예: `shadow` 는
    /// 가려진 설치를 찾으면 이 코드(또는 2)로 끝낸다.
    public static let finding: Int32 = 1

    /// **질문이 틀림**(`EX_USAGE`) — 인자 부족·모르는 옵션.
    ///
    /// 앱 잘못이 아니라 **부른 쪽**이 틀렸다. 발견으로 세면 진짜 문제가 묻힌다.
    public static let usage: Int32 = 64

    /// **설정 안 됨**(`EX_UNAVAILABLE`) — 자격증명·연결·전제가 없다.
    ///
    /// 고칠 것이 아니라 **설정하면 사라지는 것**이다. NAS·클러스터·SSH 호스트처럼
    /// 상대가 있어야 답하는 앱이 여기 해당한다. 레포 밖에서 실행해 루트를 못 찾는
    /// 경우도 같다 — 전제가 없는 것이지 고장이 아니다.
    public static let unavailable: Int32 = 69

    /// 이 코드가 "고쳐야 할 발견" 인가. 0·64·69 는 아니다.
    public static func isFinding(_ code: Int32) -> Bool {
        code != ok && code != usage && code != unavailable
    }

    /// 흔한 미도달 문구를 `unavailable` 로 가른다.
    ///
    /// 상대가 없어서 못 하는 것과 이쪽이 고장난 것은 다른 일이다. 문구 판별이
    /// 완벽할 수는 없으므로 **확실한 것만** 넣는다 — 애매하면 발견으로 남겨
    /// 사람이 보게 하는 편이 낫다.
    public static func looksUnavailable(_ message: String) -> Bool {
        let text = message.lowercased()
        return unavailableSignals.contains { text.contains($0) }
    }

    static let unavailableSignals = [
        "connection refused",
        "network is unreachable",
        "no such host",
        "i/o timeout",
        "host unreachable",
        "did you specify the right host or port",
        "no credentials",
        "no api key",
        "not logged in",
        "permission denied (publickey",
    ]
}
