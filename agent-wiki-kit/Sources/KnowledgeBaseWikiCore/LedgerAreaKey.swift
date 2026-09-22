import Foundation

/// 앱 영역(사이드바 탭)의 조종 키 — 앱과 CLI 공용 단일 진실원천(SSOT).
///
/// `memo-citation-ledger app area <key>` 가 검증하고, 앱의 `applyControlFile` 이 이 키로
/// `LedgerArea` 를 고른다. 예전엔 CLI 검증 목록과 앱 매핑이 **각자 손으로 나열**돼서,
/// 새 영역(learning·discuss·changes 등)을 앱에만 추가하면 CLI 가 조용히 거부해
/// `app area learning` 이 먹통이 됐다. 이제 CLI 는 이 목록만 보고, 앱은 이 키에서
/// `LedgerArea` 로 가는 매핑을 **exhaustive switch** 로 강제한다(케이스 누락 = 컴파일 에러).
public enum LedgerAreaKey {
    /// 조종 가능한 영역 키 — 사이드바 표시 순서에 맞춘다.
    public static let all: [String] = [
        "myNotes", "evidence", "activity", "agents", "wiki", "graph",
        "events", "changes", "discuss", "learning",
        "triage", "review", "trash", "structure", "settings",
    ]

    public static func isValid(_ key: String) -> Bool { all.contains(key) }
}
