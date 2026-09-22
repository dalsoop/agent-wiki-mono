import Foundation
#if canImport(XCTest)
import XCTest
#endif

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

// MARK: - Assertion Helpers

/// 두 값이 일치하는지 검증하고, 차이가 있다면 Mirror 덤프와 LCS 기반 라인 Diff를 출력하며 단언 실패를 발생시킵니다.
public func assertNoDifference<T1, T2>(
    _ actual: @autoclosure () throws -> T1,
    _ expected: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) rethrows {
    let act = try actual()
    let exp = try expected()
    if let difference = MiniDiff.diff(exp, act) {
        let customMessage = message()
        let failureMessage = customMessage.isEmpty ? difference : "\(customMessage)\n\(difference)"
        #if canImport(XCTest)
        XCTFail(failureMessage, file: file, line: line)
        #else
        fputs("\(file):\(line): error: assertNoDifference failed:\n\(failureMessage)\n", stderr)
        assertionFailure(failureMessage, file: file, line: line)
        #endif
    }
}

/// 명시적 레이블 `actual` / `expected`를 사용하는 단언 헬퍼.
public func assertNoDifference<T1, T2>(
    actual: @autoclosure () throws -> T1,
    expected: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) rethrows {
    let act = try actual()
    let exp = try expected()
    if let difference = MiniDiff.diff(exp, act) {
        let customMessage = message()
        let failureMessage = customMessage.isEmpty ? difference : "\(customMessage)\n\(difference)"
        #if canImport(XCTest)
        XCTFail(failureMessage, file: file, line: line)
        #else
        fputs("\(file):\(line): error: assertNoDifference failed:\n\(failureMessage)\n", stderr)
        assertionFailure(failureMessage, file: file, line: line)
        #endif
    }
}

/// XCTest 스타일 단언 헬퍼. 두 식의 결과를 비교하여 차이가 있을 경우 라인 Diff와 함께 실패를 보고합니다.
public func XCTAssertNoDifference<T1, T2>(
    _ expression1: @autoclosure () throws -> T1,
    _ expression2: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) rethrows {
    let val1 = try expression1()
    let val2 = try expression2()
    if let difference = MiniDiff.diff(val1, val2) {
        let customMessage = message()
        let failureMessage = customMessage.isEmpty ? difference : "\(customMessage)\n\(difference)"
        #if canImport(XCTest)
        XCTFail(failureMessage, file: file, line: line)
        #else
        fputs("\(file):\(line): error: XCTAssertNoDifference failed:\n\(failureMessage)\n", stderr)
        assertionFailure(failureMessage, file: file, line: line)
        #endif
    }
}

// MARK: - SelfTestCase Extension

extension SelfTestCase {
    /// `MiniDiff`를 사용하여 두 값의 차이점을 검증하는 SelfTestCase를 생성합니다.
    public static func diff<T1, T2>(
        _ name: String,
        expected: T1,
        actual: T2,
        detail: String = ""
    ) -> SelfTestCase {
        if let diffString = MiniDiff.diff(expected, actual) {
            let detailMessage = detail.isEmpty ? diffString : "\(detail)\n\(diffString)"
            return SelfTestCase(
                name: name,
                passed: false,
                expected: MiniDiff.dump(expected),
                actual: MiniDiff.dump(actual),
                detail: detailMessage
            )
        } else {
            return SelfTestCase(
                name: name,
                passed: true,
                expected: MiniDiff.dump(expected),
                actual: MiniDiff.dump(actual),
                detail: detail
            )
        }
    }
}
