import Foundation

/// SSOT 원장 기반의 마크다운 용어/도메인 치환 규칙을 제공하는 추상 프로토콜.
/// 구체 원장 구현체(DomainTermsSSOT, GenericTermsSSOT 등)에 결합되지 않고 다형적 정렬 엔진을 구성할 수 있게 합니다.
public protocol AlignRuleProvider: Sendable {
    /// 원장의 고유 식별자 (예: 버전, 스키마, 원장 이름 등)
    var ledgerIdentifier: String { get }

    /// 정렬 시 적용할 치환 규칙 목록 ((대체전문, 대체후문)).
    /// 길이가 긴 패턴이 먼저 매칭되도록 정렬되어 반환되어야 합니다.
    func replacementRules() -> [(from: String, to: String)]

    /// 원장 자체의 규칙 무결성 검증 (순환 참조, 빈 문자열, 자기 자신으로 치환 등).
    /// 발견된 결함 메시지 목록을 반환하며, 정상이면 빈 배열을 반환합니다.
    func validate() -> [String]
}
