import Foundation
import XCTest
@testable import AiCliAccountKit

final class AiCliClientTests: XCTestCase {
    /// rawValue 는 accounts.json 계약이다 — 바뀌면 저장된 계정이 통째로 안 읽힌다.
    func testRawValuesArePinned() {
        XCTAssertEqual(
            AiCliClient.allCases.map(\.rawValue),
            ["claudeCode", "codex", "gemini", "antigravity", "opencode", "grok", "kiro", "opencodex", "cursor"]
        )
        XCTAssertEqual(
            AiCliAccountKind.allCases.map(\.rawValue),
            ["oauthSession", "backendProfile"]
        )
    }

    /// rawValue 와 CLI 인자가 다른 유일 케이스.
    func testClaudeCodeArgumentSpellings() {
        XCTAssertEqual(AiCliClient.claudeCode.switchArgument, "claude")
        XCTAssertEqual(AiCliClient.claudeCode.configDirSubcommand, "claude-code")
        XCTAssertEqual(AiCliClient.claudeCode.command, "claude")
        for client in AiCliClient.allCases where client != .claudeCode {
            XCTAssertEqual(client.switchArgument, client.rawValue)
            XCTAssertEqual(client.configDirSubcommand, client.rawValue)
        }
    }

    func testIsolationEnvVarsAreDistinct() {
        let vars = AiCliClient.allCases.map(\.isolationEnvVar)
        XCTAssertEqual(Set(vars).count, vars.count)
    }

    func testOnlyClaudeCodeMergesCredentials() {
        XCTAssertFalse(AiCliClient.claudeCode.isFullSwap)
        for client in AiCliClient.allCases where client != .claudeCode {
            XCTAssertTrue(client.isFullSwap)
        }
    }

    func testCredentialsPathsHonorHome() {
        XCTAssertEqual(
            AiCliClient.codex.credentialsPath(home: "/tmp/h"),
            "/tmp/h/.codex/auth.json"
        )
        let paths = AiCliClient.allCases.map { $0.credentialsPath(home: "/tmp/h") }
        // gemini 와 antigravity 는 같은 ~/.gemini/oauth_creds.json 을 공유한다(실측).
        XCTAssertEqual(Set(paths).count, paths.count - 1)
        XCTAssertEqual(AiCliClient.antigravity.credentialsPath(home: "/tmp/h"),
                       "/tmp/h/.gemini/oauth_creds.json")
    }

    /// opencodex 경로 정본 고정. 예전엔 `credentialsPath(.opencodex)` 가
    /// `~/.codex/config.json`(= **Codex CLI 의 파일**)을 돌려줘 Codex 자격을 ocx 자격으로
    /// 오귀속했고, `ocxConfigPath`(`~/.opencodex`)·앱(`~/.openCodex`)과 세 갈래로 갈렸다.
    func testOpencodexPathsAreSiblingsUnderLowercaseHome() {
        XCTAssertEqual(
            AiCliClient.opencodex.credentialsPath(home: "/tmp/h"),
            "/tmp/h/.opencodex/auth.json"
        )
        XCTAssertEqual(
            AiCliClient.opencodex.ocxConfigPath(home: "/tmp/h"),
            "/tmp/h/.opencodex/config.json"
        )
        // auth 와 config 는 반드시 같은 디렉터리 — 묶음 스왑의 전제다.
        XCTAssertEqual(
            (AiCliClient.opencodex.credentialsPath(home: "/tmp/h") as NSString)
                .deletingLastPathComponent,
            (AiCliClient.opencodex.ocxConfigPath(home: "/tmp/h") as NSString)
                .deletingLastPathComponent
        )
        // Codex CLI 의 파일과 절대 겹치지 않는다.
        XCTAssertNotEqual(
            AiCliClient.opencodex.credentialsPath(home: "/tmp/h"),
            AiCliClient.codex.credentialsPath(home: "/tmp/h")
        )
        XCTAssertFalse(
            AiCliClient.opencodex.credentialsPath(home: "/tmp/h").contains("/.codex/")
        )
    }
}

final class AiCliAccountsReaderTests: XCTestCase {
    private func write(_ json: String) throws -> String {
        let path = NSTemporaryDirectory() + "accounts-\(UUID().uuidString).json"
        try json.write(toFile: path, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testReadsRowsAndTolerantlySkipsUnknownFields() throws {
        let id = UUID()
        let path = try write("""
        {"accounts":[
          {"id":"\(id.uuidString)","client":"claudeCode","label":"a@example.com",
           "kind":"oauthSession","sessionKey":"org-a","subscription":{"plan":"max"}}
        ],"migrated":true}
        """)
        let rows = AiCliAccountsReader(path: path).all()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, id)
        XCTAssertTrue(rows[0].hasStableID)
        XCTAssertEqual(rows[0].client, .claudeCode)
        XCTAssertEqual(rows[0].sessionKey, "org-a")
        XCTAssertEqual(AccountIdentity(rows[0])?.sessionKey, "org-a")
    }

    func testMissingFileYieldsEmptyList() {
        XCTAssertTrue(AiCliAccountsReader(path: "/nonexistent/accounts.json").all().isEmpty)
    }

    /// 이 빌드가 모르는 client 한 줄이 목록 전체를 날리면 안 된다 —
    /// 계정 관리자가 클라이언트를 하나 추가하는 순간 읽기 측 앱이 텅 비어버린다.
    func testUnknownClientRowIsDroppedButOthersSurvive() throws {
        let path = try write("""
        {"accounts":[
          {"id":"\(UUID().uuidString)","client":"claudeCode","label":"work","kind":"oauthSession"},
          {"id":"\(UUID().uuidString)","client":"someFutureCli","label":"future"},
          {"id":"\(UUID().uuidString)","client":"codex","label":"personal","kind":"oauthSession"}
        ]}
        """)
        let rows = AiCliAccountsReader(path: path).all()
        XCTAssertEqual(rows.map(\.label), ["work", "personal"])
    }

    /// 라벨 없는 행처럼 필수 필드가 빠진 줄도 그 줄만 버린다.
    func testRowMissingRequiredFieldIsSkipped() throws {
        let path = try write("""
        {"accounts":[
          {"id":"\(UUID().uuidString)","client":"codex"},
          {"id":"\(UUID().uuidString)","client":"codex","label":"ok"}
        ]}
        """)
        XCTAssertEqual(AiCliAccountsReader(path: path).all().map(\.label), ["ok"])
    }

    // MARK: - resolve (MR!2022 에서 고친 동작 — 회귀 금지)

    private func row(_ label: String, id: UUID = UUID()) -> AiCliAccountRecord {
        AiCliAccountRecord(id: id, client: .claudeCode, label: label)
    }

    func testResolvePrefersExactUUID() {
        let target = UUID()
        let pool = [row("dup", id: target), row("dup")]
        XCTAssertEqual(
            AiCliAccountsReader.resolve(selector: target.uuidString, in: pool)?.id,
            target
        )
    }

    func testResolveRefusesAmbiguousDuplicateLabels() {
        let pool = [row("dup"), row("dup")]
        XCTAssertNil(AiCliAccountsReader.resolve(selector: "dup", in: pool))
    }

    func testResolveMatchesUniqueLabelAndUUIDPrefix() {
        let target = UUID()
        let pool = [row("alice@example.com", id: target), row("bob@example.com")]
        XCTAssertEqual(AiCliAccountsReader.resolve(selector: "alice@example.com", in: pool)?.id, target)
        let prefix = String(target.uuidString.prefix(8))
        XCTAssertEqual(AiCliAccountsReader.resolve(selector: prefix, in: pool)?.id, target)
    }

    func testResolveReturnsNilWhenFuzzyMatchIsAmbiguous() {
        let pool = [row("alice@example.com"), row("alice@other.com")]
        XCTAssertNil(AiCliAccountsReader.resolve(selector: "alice", in: pool))
    }

    /// id 를 못 읽은 행은 uuid selector 후보에서 빠진다(임시 UUID 라 매칭되면 안 된다).
    func testUnstableIDRowIsNotSelectableByUUID() throws {
        let path = try write("""
        {"accounts":[{"client":"codex","label":"no-id@example.com"}]}
        """)
        let rows = AiCliAccountsReader(path: path).all()
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].hasStableID)
        XCTAssertEqual(rows[0].selector, "no-id@example.com")
        XCTAssertNil(AiCliAccountsReader.resolve(selector: rows[0].id.uuidString, in: rows))
    }
}
