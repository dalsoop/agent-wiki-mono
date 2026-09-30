import Foundation
import XCTest
@testable import InstallHealthKit

/// 재설치하면 색인에서 빠진다.
///
/// 실측 2026-08-11: business-request-intake 를 설치한 직후 ADM 은 `verdict=match` 인데
/// CLI 배너는 "소스가 더 바뀜" 을 계속 냈다. 색인이 캐시라 아무도 지워 주지 않아서다.
/// 배너의 존재 이유가 "계측기가 거짓말한다" 를 막는 것인데 배너가 거짓말하면 다음부터
/// 아무도 안 믿는다.
final class StaleInstallIndexClearTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stale-\(UUID().uuidString).json")
    }

    func testClearRemovesOnlyThatCLI() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write(
            [(cli: "a-cli", reason: "소스가 더 바뀜"), (cli: "b-cli", reason: "해시 불일치")], at: url)

        StaleInstallIndex.clear(cli: "a-cli", at: url)

        XCTAssertNil(StaleInstallIndex.reason(for: "a-cli", at: url))
        XCTAssertEqual(StaleInstallIndex.reason(for: "b-cli", at: url), "해시 불일치")
    }

    /// 색인에 없거나 파일이 없어도 죽지 않는다 — 설치 경로에서 도는 코드다.
    func testClearIsSafeWhenAbsent() {
        let url = tempURL()
        StaleInstallIndex.clear(cli: "nope", at: url)
        XCTAssertNil(StaleInstallIndex.reason(for: "nope", at: url))
    }

    /// 지운 뒤 배너가 안 뜬다.
    func testBannerSilentAfterClear() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write([(cli: "a-cli", reason: "소스가 더 바뀜")], at: url)
        StaleInstallIndex.clear(cli: "a-cli", at: url)

        var emitted = ""
        StaleInstallIndex.warnIfStale(
            cli: "a-cli", arguments: ["a-cli"], environment: [:], at: url,
            emit: { emitted += $0 })
        XCTAssertTrue(emitted.isEmpty, emitted)
    }
}

/// 배너 자체의 계약 — stderr 로 한 번, 무엇을 하면 되는지까지 같은 문자열에.
final class StaleInstallIndexBannerTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stale-\(UUID().uuidString).json")
    }

    /// 배너는 emit 한 번 — 호출자가 stdout 으로 JSON 을 파싱하는데 줄이 섞이면 깨진다.
    func testWarnEmitsOnceForStaleCLI() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write([(cli: "mycli", reason: "소스가 더 바뀜")], at: url)

        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(cli: "mycli", arguments: ["/usr/local/bin/mycli"],
                                      environment: [:], at: url, emit: { emitted.append($0) })
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].contains("재설치"), emitted[0])
        XCTAssertTrue(emitted[0].contains("소스가 더 바뀜"), emitted[0])
    }

    /// 로그를 통째로 파싱하는 자동화용 탈출구.
    func testSilenceEnvironmentSuppressesBanner() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write([(cli: "mycli", reason: "낡음")], at: url)

        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(cli: "mycli", arguments: ["mycli"],
                                      environment: [StaleInstallIndex.silenceEnvironmentKey: "1"],
                                      at: url, emit: { emitted.append($0) })
        XCTAssertTrue(emitted.isEmpty)
    }

    /// stdout 캡처에 배너가 전혀 없고 stderr 에만 출력되는 계약 검증.
    func testBannerOutputsToStderrAndLeavesStdoutClean() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write([(cli: "mycli", reason: "설치본 지연")], at: url)

        let captured = captureStandardStreams {
            StaleInstallBanner.printToStderr(
                cli: "mycli",
                arguments: ["mycli", "status"],
                environment: [:],
                at: url
            )
        }

        XCTAssertFalse(captured.stdout.contains("설치본이 소스보다 낡았습니다"),
                       "stdout 에 배너가 섞이면 안 됨: \(captured.stdout)")
        XCTAssertTrue(captured.stdout.isEmpty, "stdout 은 완전히 비어있어야 함: \(captured.stdout)")
        XCTAssertTrue(captured.stderr.contains("설치본이 소스보다 낡았습니다"),
                      "stderr 에 배너가 출력되어야 함: \(captured.stderr)")
    }

    /// --json 이 인자에 있으면 배너를 아예 내지 않는다 (quietWhenJSON 기본 true).
    func testQuietWhenJSONSuppressesBanner() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        StaleInstallIndex.write([(cli: "mycli", reason: "설치본 지연")], at: url)

        // 1) emit 클로저 기반: --json 포함 시 무출력
        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli", "list", "--json"],
            environment: [:],
            at: url,
            emit: { emitted.append($0) }
        )
        XCTAssertTrue(emitted.isEmpty, "--json 플래그가 있으면 배너가 무출력이어야 함")

        // 2) StaleInstallBanner.printToStderr: --json 인자 시 stderr/stdout 모두 무출력
        let captured = captureStandardStreams {
            StaleInstallBanner.printToStderr(
                cli: "mycli",
                arguments: ["mycli", "list", "--json"],
                environment: [:],
                at: url
            )
        }
        XCTAssertTrue(captured.stderr.isEmpty, "--json 시 stderr 에도 배너가 출력되지 않아야 함: \(captured.stderr)")
        XCTAssertTrue(captured.stdout.isEmpty, "--json 시 stdout 도 비어있어야 함: \(captured.stdout)")

        // 3) quietWhenJSON: false 지정 시에는 --json 이 있어도 출력
        var forcedEmitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli", "list", "--json"],
            environment: [:],
            at: url,
            quietWhenJSON: false,
            emit: { forcedEmitted.append($0) }
        )
        XCTAssertEqual(forcedEmitted.count, 1)
        XCTAssertTrue(forcedEmitted[0].contains("설치본이 소스보다 낡았습니다"))
    }

    private func captureStandardStreams(action: () -> Void) -> (stdout: String, stderr: String) {
        let outPipe = Pipe()
        let errPipe = Pipe()
        let savedStdout = dup(STDOUT_FILENO)
        let savedStderr = dup(STDERR_FILENO)

        dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        action()

        fflush(stdout)
        fflush(stderr)

        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        dup2(savedStdout, STDOUT_FILENO)
        dup2(savedStderr, STDERR_FILENO)
        close(savedStdout)
        close(savedStderr)

        let outData = outPipe.fileHandleForReading.availableData
        let errData = errPipe.fileHandleForReading.availableData

        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

/// 판정은 그 판정 뒤에 생긴 바이너리에 대해 말할 수 없다:
/// 바이너리 수정 시각이 색인 updatedAt 보다 뒤면 배너를 내지 않는다.
final class StaleInstallIndexTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stale-\(UUID().uuidString).json")
    }

    /// 색인 updatedAt=T, 이름이 색인에 있음, 실행 파일 수정 시각 T+60s → 배너 없음, fail-closed 에서도 exit 호출 없음.
    func testBinaryNewerThanIndexSuppressesBannerAndExit() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date()
        let tString = ISO8601DateFormatter().string(from: now)
        let snapshot = StaleInstallIndex.Snapshot(updatedAt: tString, stale: ["mycli": "소스가 더 바뀜"])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)

        let newerDate = now.addingTimeInterval(60)

        // 1. 일반 모드: 배너 없음
        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [:],
            at: url,
            executableModifiedAt: newerDate,
            emit: { emitted.append($0) }
        )
        XCTAssertTrue(emitted.isEmpty, "바이너리 수정 시각이 색인보다 뒤면 배너를 내지 않아야 함: \(emitted)")

        // 2. fail-closed 모드: 배너 없음 및 exit 호출 없음
        var failClosedEmitted: [String] = []
        var exitCode: Int32? = nil
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [StaleInstallIndex.enforceEnvironmentKey: "1"],
            at: url,
            executableModifiedAt: newerDate,
            emit: { failClosedEmitted.append($0) },
            exitHandler: { exitCode = $0 }
        )
        XCTAssertTrue(failClosedEmitted.isEmpty, "fail-closed 에서도 바이너리가 더 최신이면 배너를 내지 않아야 함")
        XCTAssertNil(exitCode, "fail-closed 에서도 바이너리가 더 최신이면 exit 을 호출하지 않아야 함")
    }

    /// 같은 조건, 수정 시각 T-60s → 배너 있음(기존 동작).
    func testBinaryOlderThanIndexEmitsBanner() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date()
        let tString = ISO8601DateFormatter().string(from: now)
        let snapshot = StaleInstallIndex.Snapshot(updatedAt: tString, stale: ["mycli": "소스가 더 바뀜"])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)

        let olderDate = now.addingTimeInterval(-60)

        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [:],
            at: url,
            executableModifiedAt: olderDate,
            emit: { emitted.append($0) }
        )
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].contains("설치본이 소스보다 낡았습니다"))

        // fail-closed 에서도 exit 호출됨
        var exitCode: Int32? = nil
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [StaleInstallIndex.enforceEnvironmentKey: "1"],
            at: url,
            executableModifiedAt: olderDate,
            emit: { _ in },
            exitHandler: { exitCode = $0 }
        )
        XCTAssertEqual(exitCode, 70)
    }

    /// 수정 시각 nil → 배너 있음(기존 동작).
    func testNilModificationDateEmitsBanner() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let now = Date()
        let tString = ISO8601DateFormatter().string(from: now)
        let snapshot = StaleInstallIndex.Snapshot(updatedAt: tString, stale: ["mycli": "소스가 더 바뀜"])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)

        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [:],
            at: url,
            executableModifiedAt: nil,
            emit: { emitted.append($0) }
        )
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].contains("설치본이 소스보다 낡았습니다"))
    }

    /// updatedAt 파싱 실패 시(형식 오류) 기존처럼 배너 출력
    func testMalformedUpdatedAtEmitsBanner() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = StaleInstallIndex.Snapshot(updatedAt: "not-a-valid-date", stale: ["mycli": "소스가 더 바뀜"])
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)

        var emitted: [String] = []
        StaleInstallIndex.warnIfStale(
            cli: "mycli",
            arguments: ["mycli"],
            environment: [:],
            at: url,
            executableModifiedAt: Date().addingTimeInterval(60),
            emit: { emitted.append($0) }
        )
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].contains("설치본이 소스보다 낡았습니다"))
    }
}

