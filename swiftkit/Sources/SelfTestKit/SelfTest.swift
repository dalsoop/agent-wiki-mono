import Foundation

/// 앱이 자기 계약을 **임시 픽스처로 증명**하는 표준 계약.
///
/// 왜(실측 2026-08-11): 한 세션에서 도구의 "성공" 보고가 9번 거짓이었다. hygiene 이
/// `applied:true` 를 내면서 worktree 를 하나도 안 지웠고, meta health 가 ✓ 인데 dispatch
/// 가 죽어 있었고, agent-ui-monitor 가 PASS 를 내면서 아무것도 안 봤다. **도구가 "확인했다"
/// 와 "확인 못 했다"를 구분하지 못해서**다 — 숫자 0이 "0건 확인"인지 "읽기 실패"인지
/// 모른다. 판정 비용이 수정 비용을 압도했다.
///
/// 이걸 근본적으로 풀려면 **앱이 자기 주장을 스스로 증명**해야 한다. 기대값을 선언하고,
/// 임시 픽스처에서 실행하고, 앱이 통과/실패를 판정한다. 사람이 즉석 셸로 조립하면
/// 틀린다(같은 세션에서 두 번 틀렸다 — `--min-age-hours` 기본값과 고아 메타).
///
/// `agent-deck worktree self-test` 가 이미 이 형태로 4/4 통과하고 있고, **그것만이
/// 이 세션에서 나를 한 번도 속이지 않은 계측**이었다. 이 kit 은 그 패턴을 일반화한다.
///
/// ## 앱 채택
///
/// 1. `AppSelfTest` 를 구현하는 구조체를 만든다 (`cases` 만 채운다)
/// 2. CLI 에 `self-test` 하위명령을 추가한다
/// 3. `SelfTestRunner.run(MyAppSelfTest(), json: wantsJSON)` 호출 — 출력·exit code 는 kit 이 담당
///
/// ## 계약
///
/// - `--json`: `{ok, result:{cases, passed, failed}}` 봉투
/// - exit: 0 = 전부 통과 · 1 = 실패 있음 · 64 = 사용법 오류
/// - **사용자 상태를 절대 건드리지 않는다** — 전부 임시 디렉터리
public protocol AppSelfTest: Sendable {
    /// 표시명.
    var name: String { get }
    /// 각 케이스를 실행해 결과를 돌려준다.
    func cases() async -> [SelfTestCase]
}

/// 단일 검증 단위. 기대값과 실제값을 비교해 앱이 판정한다.
public struct SelfTestCase: Sendable, Equatable {
    public let name: String
    public let passed: Bool
    public let expected: String
    public let actual: String
    public let detail: String

    public init(name: String, passed: Bool, expected: String, actual: String, detail: String = "") {
        self.name = name
        self.passed = passed
        self.expected = expected
        self.actual = actual
        self.detail = detail
    }

    /// 기대와 실제가 같으면 통과. 가장 흔한 형태의 편의 생성자.
    public static func equal(_ name: String, expected: String, actual: String, detail: String = "") -> SelfTestCase {
        SelfTestCase(name: name, passed: expected == actual, expected: expected, actual: actual, detail: detail)
    }

    /// 조건만으로 판정. "워크트리가 제거됐다" 처럼 불리언 판정이 자연스러운 경우.
    public static func check(_ name: String, _ condition: Bool, detail: String, expected: String = "true", actual: String? = nil) -> SelfTestCase {
        SelfTestCase(name: name, passed: condition, expected: expected, actual: actual ?? (condition ? "true" : "false"), detail: detail)
    }
}

/// 전체 리포트.
public struct SelfTestReport: Sendable {
    public let cases: [SelfTestCase]
    public var passed: Int { cases.count { $0.passed } }
    public var failed: Int { cases.count { !$0.passed } }
    public var allPassed: Bool { failed == 0 }

    public init(cases: [SelfTestCase]) { self.cases = cases }
}

/// CLI `self-test` 하위명령의 실행·출력·exit code 를 담당한다.
/// 앱은 `cases()` 만 구현하고 이 runner 를 부른다.
public enum SelfTestRunner {
    /// 테스트를 실행하고 결과를 출력한 뒤 exit 한다.
    public static func run(_ test: AppSelfTest, json: Bool) -> Never {
        let report = runSync(test)

        if json {
            let envelope: [String: Any] = [
                "ok": report.allPassed,
                "result": [
                    "cases": report.cases.map { c -> [String: Any] in
                        [
                            "name": c.name,
                            "passed": c.passed,
                            "expected": c.expected,
                            "actual": c.actual,
                            "detail": c.detail,
                        ]
                    },
                    "passed": report.passed,
                    "failed": report.failed,
                ]
            ]
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
                if let s = String(data: data, encoding: .utf8) {
                    FileHandle.standardOutput.write(Data(s.utf8)) // allow:debug — CLI JSON 출력
                }
            } catch {
                FileHandle.standardError.write(Data("self-test JSON 직렬화 실패: \(error)\n".utf8))
            }
        } else {
            let out = FileHandle.standardOutput // allow:debug — CLI 텍스트 출력
            func p(_ s: String) { out.write(Data((s + "\n").utf8)) }
            p("\(test.name) self-test: \(report.passed)/\(report.cases.count) 통과")
            for c in report.cases {
                p("  \(c.passed ? "✓" : "✗") \(c.name) — \(c.detail)")
                if !c.passed {
                    p("      기대: \(c.expected)")
                    p("      실제: \(c.actual)")
                }
            }
        }
        exit(report.allPassed ? 0 : 1)
    }

    /// 동기 래퍼 — async `cases()` 를 `DispatchSemaphore` 로 실행한다.
    /// (CLI 진입점이 async 컨텍스트가 아닐 때가 많아서.)
    static func runSync(_ test: AppSelfTest) -> SelfTestReport {
        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var report: SelfTestReport? }
        let box = Box()
        Task {
            box.report = SelfTestReport(cases: await test.cases())
            sem.signal()
        }
        sem.wait()
        return box.report!
    }
}
