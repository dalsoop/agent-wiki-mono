import Foundation
import CommandKit
import AppPathsKit

/// AgentWikiLocal 도메인 로직. 시스템 명령 호출 + 출력 파싱을 담당한다.
/// (root 가 필요하면 PrivilegedKit 의 PrivilegedRunner 사용)
public enum AgentWikiLocalError: Error, Sendable, Equatable {
    case commandFailed(String)
}

public struct AgentWikiLocalService: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// 설정·작업 sqlite 를 연다. GUI 첫 로드에서 호출.
    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: AppPaths.sqliteFile)
    }

    /// 데모 상태: `uname -s`. 실제 앱에서 도메인 명령으로 교체.
    /// 실패는 문자열로 삼키지 않는다.
    public func status() async throws -> String {
        let r = await runner.run(AppPaths.uname, ["-s"])
        guard r.ok else {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? "uname failed (exit \(r.exitCode))" : detail
            throw AgentWikiLocalError.commandFailed(message)
        }
        return r.trimmedStdout
    }
}
