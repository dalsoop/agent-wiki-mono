import Foundation
// CommandKit 을 re-export 해 DBViewerKit 소비자가 CommandResult 등을 그대로 쓴다.
@_exported import CommandKit

/// 셸 명령 하나(실행 파일 경로 + 인자). 엔진별 CommandBuilder 가 생성하고
/// `DatabaseCommandRunning` 이 실행한다. (예전 각 앱의 `ShellCommand` 구조체를 대체)
public struct DatabaseCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

/// `DatabaseCommand` 실행 추상화. 테스트는 목을 주입한다.
/// 결과는 CommandKit 의 `CommandResult`(stdout·stderr·exitCode)를 재사용한다.
public protocol DatabaseCommandRunning: Sendable {
    func run(_ command: DatabaseCommand) async -> CommandResult
}

/// 기본 구현 — 실제 프로세스 실행은 CommandKit `ProcessCommandRunner` 에 위임한다.
/// (예전 각 앱에 복붙돼 있던 `ProcessShellRunner` 의 Process 코드를 CommandKit 으로 접었다.)
public struct ProcessDatabaseCommandRunner: DatabaseCommandRunning {
    private let inner: ProcessCommandRunner

    public init() {
        self.inner = ProcessCommandRunner()
    }

    public func run(_ command: DatabaseCommand) async -> CommandResult {
        await inner.run(command.executable, command.arguments)
    }
}

public extension CommandResult {
    /// 예전 각 앱의 `ShellResult(exitCode:stdout:stderr:)` 인자 순서를 유지하는 편의 init.
    /// (마이그레이션한 클라이언트·테스트가 레이블 순서를 안 바꿔도 되게 한다)
    init(exitCode: Int32, stdout: String, stderr: String) {
        self.init(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

/// 엔진별 명령 생성 seam — psql/kubectl, mysql CLI 등 셸 기반 엔진이 이행한다.
/// (네이티브 엔진(SQLite)은 셸을 안 쓰므로 이행하지 않는다.)
public protocol DatabaseCommandBuilder: Sendable {
    func discoveryCommand() -> DatabaseCommand
    func runQueryCommand(target: DatabaseTarget, sql: String) -> DatabaseCommand
    func listTablesSQL() -> String
}
