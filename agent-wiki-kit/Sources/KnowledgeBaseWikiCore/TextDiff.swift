import Foundation

/// 개정 두 판의 라인 단위 diff — 나무위키 '비교'(역사) 대응. LCS 기반.
/// 지식 문서 본문 크기(수백 줄)에 O(m·n)이면 충분. 순수·테스트 가능.
public enum DiffLine: Sendable, Equatable {
    case same(String)
    case added(String)
    case removed(String)
}

public enum TextDiff {
    public static func lines(_ old: String, _ new: String) -> [DiffLine] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let m = a.count, n = b.count
        // LCS 길이 테이블
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var out: [DiffLine] = []
        var i = 0, j = 0
        while i < m && j < n {
            if a[i] == b[j] { out.append(.same(a[i])); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { out.append(.removed(a[i])); i += 1 }
            else { out.append(.added(b[j])); j += 1 }
        }
        while i < m { out.append(.removed(a[i])); i += 1 }
        while j < n { out.append(.added(b[j])); j += 1 }
        return out
    }

    /// 요약 — (추가 줄, 삭제 줄).
    public static func stat(_ diff: [DiffLine]) -> (added: Int, removed: Int) {
        var a = 0, r = 0
        for line in diff { if case .added = line { a += 1 }; if case .removed = line { r += 1 } }
        return (a, r)
    }
}
