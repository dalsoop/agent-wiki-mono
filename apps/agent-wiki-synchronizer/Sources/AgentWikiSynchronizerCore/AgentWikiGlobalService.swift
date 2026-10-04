import Foundation
import CommandKit
import AppPathsKit

/// AgentWikiGlobal 도메인 로직. 시스템 명령 호출 + 출력 파싱을 담당한다.
/// (root 가 필요하면 PrivilegedKit 의 PrivilegedRunner 사용)
public enum AgentWikiGlobalError: Error, Sendable, Equatable {
    case commandFailed(String)
}

public struct AgentWikiGlobalService: Sendable {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// 설정·작업 sqlite 를 연다. GUI 첫 로드에서 호출.
    public func ensureDurableStore() throws {
        try DurableAppLayout.ensureDatabase(at: AppPaths.sqliteFile)
    }

    /// 동기화 표시: `agent-law` 의 마지막 동기화 시각·커밋 대기 수·push 여부(`AgentLawSyncSummary`).
    public func status() async throws -> String {
        AgentLawSyncSummary.current()
    }
}
