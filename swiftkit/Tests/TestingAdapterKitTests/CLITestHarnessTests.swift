import Testing
import Foundation
import ArgumentParser
@testable import TestingAdapterKit

// MARK: - Test Commands

private struct EchoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "echo-cmd",
        abstract: "Echoes input text"
    )

    @Argument(help: "Text to echo")
    var text: String

    @Flag(name: .shortAndLong, help: "Convert to uppercase")
    var uppercase: Bool = false

    mutating func run() throws {
        if uppercase {
            print(text.uppercased())
        } else {
            print(text)
        }
    }
}

private struct FailingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "failing-cmd",
        abstract: "A command that always fails"
    )

    @Option(name: .shortAndLong, help: "Custom exit error code")
    var code: Int32 = 1

    mutating func run() throws {
        throw ExitCode(code)
    }
}

private struct ValidationCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "val-cmd")

    @Option(name: .shortAndLong)
    var count: Int

    mutating func validate() throws {
        guard count > 0 else {
            throw ValidationError("count must be positive")
        }
    }

    mutating func run() throws {
        print("count: \(count)")
    }
}

private struct EnvEchoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "env-echo")

    @Argument
    var key: String

    mutating func run() throws {
        let value = ProcessInfo.processInfo.environment[key] ?? "<nil>"
        print(value)
    }
}

private struct AsyncSleepEchoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "async-cmd")

    @Argument
    var message: String

    func run() async throws {
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        print("async: \(message)")
    }
}

// MARK: - Test Suite

@Suite("CLITestHarnessTests")
struct CLITestHarnessTests {

    @Test("정상 인자 전달 및 stdout 캡처")
    func testEchoExecution() {
        let result = CLITestHarness.run(EchoCommand.self, arguments: ["hello-world"])

        #expect(result.exitCode == 0)
        #expect(result.isSuccess == true)
        #expect(result.trimmedStdout == "hello-world")
        #expect(result.trimmedStderr.isEmpty)
        #expect(result.duration >= 0)
    }

    @Test("플래그 옵션 처리 및 변환 확인")
    func testFlagParsing() {
        let result = CLITestHarness.run(EchoCommand.self, arguments: ["hello", "--uppercase"])

        #expect(result.exitCode == 0)
        #expect(result.trimmedStdout == "HELLO")
    }

    @Test("ExitCode 에러 캡처")
    func testFailingCommand() {
        let result = CLITestHarness.run(FailingCommand.self, arguments: ["--code", "42"])

        #expect(result.exitCode == 42)
        #expect(result.isSuccess == false)
    }

    @Test("유효성 검사 실패(ValidationError) 및 stderr 캡처")
    func testValidationError() {
        let result = CLITestHarness.run(ValidationCommand.self, arguments: ["--count", "-1"])

        #expect(result.exitCode != 0)
        #expect(result.isSuccess == false)
        #expect(result.stderr.contains("count must be positive"))
    }

    @Test("도움말(--help) 호출 시 exitCode 0 및 안내문 캡처")
    func testHelpRequest() {
        let result = CLITestHarness.run(EchoCommand.self, arguments: ["--help"])

        #expect(result.exitCode == 0)
        #expect(result.isSuccess == true)
        #expect(result.stdout.contains("OVERVIEW: Echoes input text") || result.stdout.contains("USAGE:"))
        #expect(result.stdout.contains("--uppercase"))
    }

    @Test("환경변수 격리 및 주입 검증")
    func testEnvironmentInjection() {
        let testKey = "TEST_HARNESS_KEY"
        let testVal = "injected-secret-token"

        let result = CLITestHarness.run(
            EnvEchoCommand.self,
            arguments: [testKey],
            environment: [testKey: testVal]
        )

        #expect(result.exitCode == 0)
        #expect(result.trimmedStdout == testVal)

        // 실행 완료 후 외부 환경변수가 원복되었는지 확인
        #expect(ProcessInfo.processInfo.environment[testKey] == nil)
    }

    @Test("AsyncParsableCommand 비동기 실행 및 캡처 (runAsync)")
    func testAsyncCommandExecution() async {
        let result = await CLITestHarness.runAsync(
            AsyncSleepEchoCommand.self,
            arguments: ["swift-concurrency"]
        )

        #expect(result.exitCode == 0)
        #expect(result.isSuccess == true)
        #expect(result.trimmedStdout == "async: swift-concurrency")
    }
}
