import Foundation

/// Repository 중심 화면의 CLI 조종 키. GUI와 CLI가 같은 공개 목적지 집합을 사용한다.
/// 키는 화면 목적지의 이름 그대로다. ledger 3 원장의 메뉴(목차·기록·심급·드리밍·모델 신빙성)는 `law` 로 시작하고,
/// 지금 연 원장의 메뉴에 없는 목적지는 화면이 무시한다.
public enum RepositoryDestinationKey {
    public static let all: [String] = [
        "overview", "knowledge", "tasks", "promotion", "contributors", "administration",
        "lawContents", "lawRecords", "lawCourt", "lawDream", "lawCredibility",
    ]

    public static func isValid(_ key: String) -> Bool { all.contains(key) }
}
