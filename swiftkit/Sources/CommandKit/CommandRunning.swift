import Foundation

/// 로컬 명령 실행 추상화. 테스트는 목 구현(`MockCommandRunner`)을 주입한다.
public protocol CommandRunning: Sendable {
    /// 명세(`CommandSpecification`)에 따라 외부 명령을 실행한다.
    func run(_ spec: CommandSpecification) async -> CommandResult

    /// 명세(`CommandSpecification`)에 따라 외부 명령의 라인별 출력을 비동기 스트림으로 제공한다.
    func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error>

    /// 실행 파일 경로와 인자로 명령을 실행한다 (레거시 및 기본 인터페이스).
    ///
    /// - Parameter timeout: 만료 시 프로세스 그룹에 SIGTERM을 전송하고 필요 시 SIGKILL로 승격한다.
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult
}

public extension CommandRunning {
    /// `CommandSpecification` 기반 실행의 기본 구현 (기존 launchPath, arguments 메서드로 위임).
    func run(_ spec: CommandSpecification) async -> CommandResult {
        await run(spec.launchPath, spec.arguments, timeout: spec.timeout)
    }

    /// 기존 launchPath, arguments 기반 실행의 기본 구현 (`CommandSpecification`으로 변환하여 위임).
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        await run(CommandSpecification(launchPath, arguments, timeout: timeout))
    }

    /// timeout 없는 편의 오버로드.
    func run(_ launchPath: String, _ arguments: [String]) async -> CommandResult {
        await run(launchPath, arguments, timeout: nil)
    }

    /// 라인별 비동기 스트림 기본 구현 (run(spec) 실행 결과를 비동기 방출).
    func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let result = await self.run(spec)
                guard !Task.isCancelled else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
                    continuation.yield(.stdout(String(line)))
                }
                for line in result.stderr.split(separator: "\n", omittingEmptySubsequences: false) where !result.stderr.isEmpty {
                    continuation.yield(.stderr(String(line)))
                }
                switch (result.timedOut, result.exitCode) {
                case (true, _):
                    continuation.finish(throwing: CommandError.timedOut(spec.timeout ?? 0))
                case (false, let code) where code != 0:
                    continuation.finish(throwing: CommandError.nonZeroExit(exitCode: code, stderr: result.stderr))
                default:
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// 편의 오버로드: launchPath와 arguments로 lines 스트림 호출.
    func lines(_ launchPath: String, _ arguments: [String] = [], timeout: TimeInterval? = nil) -> AsyncThrowingStream<CommandLineOutput, Error> {
        lines(CommandSpecification(launchPath, arguments, timeout: timeout))
    }
}
