import Foundation

/// agent-law(ledger 3) 기본 이름의 정본. 다른 소스는 이 이름을 다시 적지 않고 여기를 부른다.
///
/// 근거: 결정 0007("전역 CLI 의 기본 원장은 `agent-law` 다", "R2 전용 버킷 `agent-law`"),
/// docs/business-rules.md "# agent-law(ledger 3)" 원장 구성 표.
/// 원장의 **층**은 이름에서 판정하지 않는다 — 호스트 설정(`world add --layer`·`world set-layer`)에 기록된 값을 쓴다.
public enum LawLedgerDefaults {
    /// 전역 CLI·앱이 `--world` 없이 여는 공유 원장 world 이름.
    public static let sharedWorldName = "agent-law"
    /// 세션 조각·증거물을 두는 R2 전용 버킷 이름. 호스트 설정 `world storage --bucket` 이 이긴다.
    public static let bucketName = "agent-law"
}
