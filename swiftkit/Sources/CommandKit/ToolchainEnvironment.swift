import Foundation

/// 자식 프로세스가 물려받으면 **SwiftPM 빌드를 못 하게 만드는** 환경변수를 걷어낸다.
///
/// 실사고(2026-09-03): `app-build-manager ship` 의 `[1/6] swift test` 가
/// `sandbox-exec: execvp() of '<pkg>-manifest' failed: No such file or directory`
/// 로 죽었다. 원인은 부모(에이전트 런타임)가 물려준 `SWIFT_EXEC=/usr/bin/swift` 다.
/// SwiftPM 은 `SWIFT_EXEC` 를 **컴파일러**로 알고 패키지 매니페스트를 컴파일하는데,
/// `/usr/bin/swift` 는 인터프리터 드라이버라 `-o` 를 받아도 바이너리를 남기지 않는다.
/// 산출물이 없으니 뒤이은 `execvp` 가 실패한다.
///
/// 지금까지의 대처는 호출부마다 `env -u SWIFT_EXEC` 를 앞에 붙이는 것이었다. 그건
/// 사람이 매번 기억해야 하는 요령이지 수리가 아니다 — 오염된 변수는 **자식을 띄우는
/// 쪽**에서 건다. 그래서 CommandKit 러너들이 spawn 직전에 이걸 통과시킨다.
public enum ToolchainEnvironment {
    /// `SWIFT_EXEC` 값이 컴파일러로 쓸 수 **없는** 값인가.
    ///
    /// - 빈 값: 경로로 읽혀 즉시 실패한다.
    /// - basename 이 `swift`: 인터프리터 드라이버다. 컴파일러 자리에 놓으면 산출물이 없다.
    ///
    /// 그 밖의 값(`swiftc`, 커스텀 래퍼, 다른 툴체인 경로)은 **건드리지 않는다** —
    /// 일부러 넣은 값일 수 있고, 넓게 지우면 이 함수가 새로운 함정이 된다.
    public static func isUnusableSwiftExec(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return (trimmed as NSString).lastPathComponent == "swift"
    }

    /// 못 쓰는 `SWIFT_EXEC` 를 **지운 사본**을 돌려준다.
    ///
    /// 빈 문자열로 덮지 않고 키 자체를 지운다 — SwiftPM 은 빈 값도 경로로 읽는다.
    /// 지우면 SwiftPM 이 툴체인에서 컴파일러를 스스로 찾는다(원래 동작).
    public static func sanitized(_ environment: [String: String]) -> [String: String] {
        var env = environment
        if let exec = env["SWIFT_EXEC"], isUnusableSwiftExec(exec) {
            env.removeValue(forKey: "SWIFT_EXEC")
        }
        return env
    }

    /// 현재 프로세스 환경을 정화한 사본. `Process.environment` 에 그대로 넣는다.
    public static var sanitizedCurrent: [String: String] {
        sanitized(ProcessInfo.processInfo.environment)
    }
}
