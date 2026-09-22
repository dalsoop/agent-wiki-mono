import Foundation
import Testing
@testable import InteropKit

@Suite("관측 계약")
struct ObservabilityContractTests {
    @Test("status 가 없으면 그것만 센다 — 없는 명령의 --json 을 따로 세면 숫자가 부푼다")
    func statusMissingCountsOnce() {
        let v = ObservabilityContract.declaredViolations(
            commands: [(name: "list", json: true)], cliInstalled: true)
        #expect(v == [.noStatus])
    }

    @Test("status 는 있는데 --json 이 없으면 그것만")
    func jsonMissing() {
        let v = ObservabilityContract.declaredViolations(
            commands: [(name: "status", json: false)], cliInstalled: true)
        #expect(v == [.noJSON])
    }

    @Test("계약을 다 지키면 위반이 없다")
    func conforming() {
        let v = ObservabilityContract.declaredViolations(
            commands: [(name: "status", json: true)], cliInstalled: true)
        #expect(v.isEmpty)
        #expect(ObservabilityContract.Conformance(app: "a", cli: "a", violations: v).conforms)
    }

    @Test("미설치는 status 여부와 별개로 함께 잡힌다 — 고치는 일이 다르다")
    func notInstalledIsIndependent() {
        let v = ObservabilityContract.declaredViolations(
            commands: [(name: "status", json: true)], cliInstalled: false)
        #expect(v == [.notInstalled])
    }

    @Test("EX_USAGE 만 '인자를 요구함' 이다 — 발견(1)·미설정(69)과 섞지 않는다")
    func observed() {
        #expect(ObservabilityContract.observedViolation(exitCode: 64) == .needsArguments)
        #expect(ObservabilityContract.observedViolation(exitCode: 1) == nil)
        #expect(ObservabilityContract.observedViolation(exitCode: 69) == nil)
        #expect(ObservabilityContract.observedViolation(exitCode: 0) == nil)
    }

    @Test("모든 위반은 고치는 방법을 스스로 말한다")
    func everyViolationHasRemedy() {
        for kind in ObservabilityContract.Violation.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.remedy.isEmpty)
        }
    }

    @Test("이름만 있는 cli 는 PATH 에서 찾는다 — 이게 없어 8건 중 7건이 거짓 미설치였다")
    func resolvesBareNameOnPATH() {
        let dir = NSTemporaryDirectory() + "obs-contract-\(UUID().uuidString)"
        do { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch { _ = error }
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let exe = dir + "/pretend-cli"
        FileManager.default.createFile(atPath: exe, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])

        #expect(ObservabilityContract.resolvedExecutable("pretend-cli",
                                                         environment: ["PATH": dir]) == exe)
        #expect(ObservabilityContract.resolvedExecutable("nope", environment: ["PATH": dir]) == nil)
    }

    @Test("절대 경로는 PATH 를 보지 않는다 — 있으면 그대로, 없으면 nil")
    func absolutePathIsTakenLiterally() {
        #expect(ObservabilityContract.resolvedExecutable("/bin/sh", environment: [:]) == "/bin/sh")
        #expect(ObservabilityContract.resolvedExecutable("/nonexistent/x", environment: [:]) == nil)
    }

    @Test("PATH 가 없으면 기본 경로를 지어내지 않는다")
    func emptyPATHFindsNothing() {
        #expect(ObservabilityContract.resolvedExecutable("sh", environment: [:]) == nil)
        #expect(ObservabilityContract.resolvedExecutable("") == nil)
    }
}
