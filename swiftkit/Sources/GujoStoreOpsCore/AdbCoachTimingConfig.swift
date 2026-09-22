import Foundation

/// adb 코치 폴링 타이밍의 단일 진실의 원천.
///
/// 값이 두 군데 살면 한쪽만 바뀐다. 실제로 CLI 의 `--interval`·`--timeout` 기본값이
/// `AdbConnectCoach.watch` 의 기본값을 그대로 베껴 적고 있었다 — 코치 쪽 주기를 바꿔도
/// CLI 는 옛 값을 계속 썼다. 두 소비자가 여기 하나를 본다.
public enum AdbCoachTimingConfig {
    /// 폴링 간격(초). 기기 상태가 사람 손에 따라 바뀌는 속도라, 더 촘촘히 돌아도
    /// 얻는 게 없고 adb 를 헛되이 때린다.
    public static let watchIntervalSeconds: Double = 1.5

    /// `--watch` 최대 대기(초). 10분이면 케이블 연결·USB 디버깅 승인·재연결까지
    /// 사람이 끝낼 시간이다. 넘으면 TIMEOUT 으로 끊어 에이전트 루프를 붙잡지 않는다.
    public static let watchTimeoutSeconds: Double = 600
}
