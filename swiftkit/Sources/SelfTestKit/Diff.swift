import Foundation

/// 순수 Swift Mirror 리플렉션과 LCS(Longest Common Subsequence) 라인 단위 Diff 알고리즘을 사용한 경량 Diff 엔진.
/// 외부 의존성이 0개이며 결정론적(deterministic) 출력을 보장합니다.
public enum MiniDiff: Sendable {
    
    // MARK: - Public API
    
    /// 두 임의의 값의 차이점을 계산하여 라인 단위 Diff 문자열을 반환합니다.
    /// 차이가 없으면 `nil`을 반환합니다.
    public static func diff<T1, T2>(_ expected: T1, _ actual: T2) -> String? {
        let expectedDump = dump(expected)
        let actualDump = dump(actual)
        return diff(expected: expectedDump, actual: actualDump)
    }
    
    /// 두 문자열의 라인 단위 LCS Diff를 계산합니다.
    /// 차이가 없으면 `nil`을 반환합니다.
    public static func diff(expected: String, actual: String) -> String? {
        let expectedLines = expected.components(separatedBy: "\n")
        let actualLines = actual.components(separatedBy: "\n")
        
        if expectedLines == actualLines {
            return nil
        }
        
        let diffLines = computeLCSDiff(expectedLines, actualLines)
        var output: [String] = []
        output.append("Difference: (- Expected, + Actual)")
        for line in diffLines {
            output.append(line)
        }
        return output.joined(separator: "\n")
    }
    
    /// 순수 Swift Mirror 리플렉션을 사용하여 값을 구조화되고 정렬된(결정론적) 문자열로 덤프합니다.
    public static func dump<T>(_ value: T) -> String {
        dumpAny(value, depth: 0, maxDepth: 30)
    }
    
    // MARK: - Internal LCS Algorithm
    
    private static func backtrackStep(
        i: inout Int,
        j: inout Int,
        lines1: [String],
        lines2: [String],
        dp: [[Int]]
    ) -> String {
        let isMatch = (i > 0 && j > 0) && (lines1[i - 1] == lines2[j - 1])
        if isMatch {
            i -= 1
            j -= 1
            return "  \(lines1[i])"
        }
        let takeInsertion = j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])
        if takeInsertion {
            j -= 1
            return "+ \(lines2[j])"
        }
        i -= 1
        return "- \(lines1[i])"
    }

    /// 최장 공통 부분 수열(LCS)을 계산하고 라인 단위 diff(+ / - / 동일)를 역추적합니다.
    static func computeLCSDiff(_ lines1: [String], _ lines2: [String]) -> [String] {
        let m = lines1.count
        let n = lines2.count

        // DP Table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0..<m {
            for j in 0..<n {
                if lines1[i] == lines2[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i][j + 1], dp[i + 1][j])
                }
            }
        }

        // Backtracking
        var result: [String] = []
        var i = m
        var j = n

        while i > 0 || j > 0 {
            result.append(backtrackStep(i: &i, j: &j, lines1: lines1, lines2: lines2, dp: dp))
        }

        return result.reversed()
    }

    // MARK: - Internal Mirror Reflection Dumper

    static func escapeString(_ string: String) -> String {
        MiniDiffDumper.escapeString(string)
    }

    static func dumpAny(_ value: Any?, depth: Int, maxDepth: Int) -> String {
        MiniDiffDumper.dumpAny(value, depth: depth, maxDepth: maxDepth)
    }
}

// 단언 도우미(assertNoDifference·XCTAssertNoDifference)는 여기 두지 않는다. 운영 킷이
// `#if canImport(XCTest) import XCTest` 를 하면 Xcode 가 깔린 Mac 에서 조건이 참이 되어
// 이 킷을 쓰는 앱 실행 파일이 libXCTestSwiftSupport 에 링크되고, 설치본은 시작하자마자
// "Library missing" 으로 죽는다(2026-09-24 AgentWikiGlobal ship 품질 게이트 실측).
// 도우미는 쓰는 곳이 없었다 — 필요하면 테스트 전용 타깃에 둔다.
