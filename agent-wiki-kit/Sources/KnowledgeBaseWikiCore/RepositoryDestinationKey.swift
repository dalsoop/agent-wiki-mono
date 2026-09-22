import Foundation

/// Repository 중심 화면의 CLI 조종 키. GUI와 CLI가 같은 공개 목적지 집합을 사용한다.
public enum RepositoryDestinationKey {
    public static let all: [String] = [
        "overview", "knowledge", "tasks", "promotion", "contributors", "administration",
    ]

    public static func isValid(_ key: String) -> Bool { all.contains(key) }
}
