import Foundation

/// 함대 표준 건강 필드 계약 — status/lastError 파생 규칙의 단일 구현.
/// 정본 계약은 `Documentation/state-mirror-kit.md` 의 "표준 건강 필드".
///
/// VW 키체인 사고(2026-08-23)에서 에러를 화면에만 띄운 설치본은 원문을 소급할 수
/// 없었다 — 모든 게시 앱이 같은 파생을 써서 이 관측 구멍을 메운다. 앱별 State
/// 타입은 다양하므로 스키마 타입은 두지 않고 파생만 공유한다.
public enum StateMirrorHealth {
    /// 문제 없음.
    public static let ok = "ok"
    /// `lastError` 가 있는 상태.
    public static let error = "error"
    /// untyped(`publishJSONObject`) 게시에서 lastError 를 넣는 키.
    public static let lastErrorKey = "lastError"

    /// `lastError` 유무에서 표준 status 를 파생한다.
    /// nil 이면 키를 아예 생략하는 계약이라 빈 문자열은 없음으로 취급한다.
    public static func status(lastError: String?) -> String {
        guard let lastError, !lastError.isEmpty else { return ok }
        return error
    }
}
