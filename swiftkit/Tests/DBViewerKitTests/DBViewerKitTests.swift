import XCTest
@testable import DBViewerKit

final class DBViewerKitTests: XCTestCase {
    func testSQLSafetyAllowsReadOnlySingleStatement() {
        XCTAssertTrue(SQLSafety.isReadOnly("select 1"))
        XCTAssertFalse(SQLSafety.isReadOnly("select 1; drop table t"))
        XCTAssertFalse(SQLSafety.isReadOnly("delete from t"))
    }

    func testTSVParserRoundTrip() throws {
        let result = try TSVParser.parse("a\tb\n1\t2\n")
        XCTAssertEqual(result.columns, ["a", "b"])
        XCTAssertEqual(result.rows, [["1", "2"]])
    }

    func testProcessDatabaseCommandRunnerRunsEcho() async {
        let runner = ProcessDatabaseCommandRunner()
        let result = await runner.run(DatabaseCommand(executable: "/bin/echo", arguments: ["hi"]))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.trimmedStdout, "hi")
    }

    func testLaravelClassifier() {
        XCTAssertTrue(LaravelTableClassifier.isFramework("migrations"))
        XCTAssertTrue(LaravelTableClassifier.isFramework("telescope_entries"))
        XCTAssertFalse(LaravelTableClassifier.isFramework("users"))
    }

    /// 기본 프리셋은 미설정이다 — 퇴역한 호스트를 기본값으로 갖지 않는다.
    func testDefaultPresetIsUnconfigured() {
        let preset = ConnectionPreset()
        XCTAssertEqual(preset.id, ConnectionPreset.unconfiguredID)
        XCTAssertEqual(preset.jumpHost, "")
        XCTAssertEqual(preset.kubeHost, "")
        XCTAssertFalse(preset.hasConnectionTarget)
        XCTAssertEqual(ConnectionPreset.unconfigured, preset)

        let settings = DatabaseViewerSettings()
        XCTAssertEqual(settings.profiles, [.unconfigured])
        XCTAssertEqual(settings.selectedProfile, .unconfigured)
    }

    func testPresetWithBothHostsHasConnectionTarget() {
        let preset = ConnectionPreset(hosts: .init(
            id: "p", name: "p",
            jumpHost: "root@db-jump.example.internal",
            kubeHost: "root@kube.example.internal"
        ))
        XCTAssertTrue(preset.hasConnectionTarget)
        var missingKube = preset
        missingKube.kubeHost = "  "
        XCTAssertFalse(missingKube.hasConnectionTarget)
    }

    /// 저장본에 남은 퇴역 기본 프리셋은 디코드 때 버려지고, 선택도 미설정으로 돌아간다.
    func testDecodeDropsRetiredDefaultPreset() throws {
        let json = #"""
        {"profiles":[{"id":"k3s-prod-via-pve","name":"old","jumpHost":"root@192.0.2.50",
          "kubeHost":"root@192.0.2.100","namespaceFilter":"","defaultDatabase":"",
          "queryTimeoutSeconds":30,"defaultLimit":100}],
         "selectedProfileID":"k3s-prod-via-pve","readOnlyMode":true}
        """#
        let settings = try JSONDecoder().decode(DatabaseViewerSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.profiles.contains { ConnectionPreset.retiredPresetIDs.contains($0.id) })
        XCTAssertEqual(settings.profiles, [.unconfigured])
        XCTAssertEqual(settings.selectedProfileID, ConnectionPreset.unconfiguredID)
        XCTAssertFalse(settings.selectedProfile.hasConnectionTarget)
    }

    /// 퇴역 프리셋만 걸러 내고 사용자가 만든 프로필은 그대로 둔다.
    func testDecodeKeepsExplicitProfilesNextToRetiredOne() throws {
        let json = #"""
        {"profiles":[
          {"id":"k3s-prod-via-pve","name":"old","jumpHost":"root@192.0.2.50",
           "kubeHost":"root@192.0.2.100","namespaceFilter":"","defaultDatabase":"",
           "queryTimeoutSeconds":30,"defaultLimit":100},
          {"id":"mine","name":"mine","jumpHost":"root@db-jump.example.internal",
           "kubeHost":"root@kube.example.internal","namespaceFilter":"","defaultDatabase":"",
           "queryTimeoutSeconds":30,"defaultLimit":100}],
         "selectedProfileID":"mine","readOnlyMode":true}
        """#
        let settings = try JSONDecoder().decode(DatabaseViewerSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.profiles.map(\.id), ["mine"])
        XCTAssertEqual(settings.selectedProfile.jumpHost, "root@db-jump.example.internal")
    }

    func testConnectionNotConfiguredErrorIsActionable() {
        let message = DatabaseClientError.connectionNotConfigured("Unconfigured").errorDescription ?? ""
        XCTAssertTrue(message.contains("연결 대상을 설정하세요"), message)
        XCTAssertTrue(message.contains("jumpHost"), message)
    }
}
