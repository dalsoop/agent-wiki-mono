import Foundation

/// content-addressed 원장 객체의 공통 계약.
///
/// 두 앱의 구체 타입(KBW `LedgerObject`, forge `ForgeObject`)은 필드 집합이 달라
/// (KBW: observes·origin·tags·source / forge: scope·session·branch·target) 하나로
/// 합치지 않는다. 대신 각자 이 프로토콜에 conform 해 **주소 계산·검증**만 공유한다.
///
/// 규약: `canonicalCore()` 는 `id` 와 `sha256` 을 **제외한** 모든 태생 필드 + 본문을
/// 결정적 순서로 직렬화한 문자열이다(자기참조 순환 회피 — git object·trusty URI 방식).
public protocol CitationLedgerObject {
    /// id·sha256 을 제외한 결정적 직렬화. 이 문자열의 sha256 이 곧 객체의 id.
    func canonicalCore() -> String
}

extension CitationLedgerObject {
    /// 정체성 = 주소 = 무결성. `id = sha256(canonicalCore)`.
    public var contentID: String { CitationLedger.sha256Hex(canonicalCore()) }

    /// 자기검증 — 주어진 id 가 실제 내용 해시와 일치하는가(변조·오배치 탐지).
    public func verifyContentID(_ id: String) -> Bool { id == contentID }
}
