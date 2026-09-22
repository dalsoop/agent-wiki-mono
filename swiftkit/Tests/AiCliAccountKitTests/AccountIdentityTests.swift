import Foundation
import XCTest
@testable import AiCliAccountKit

/// 테스트용 최소 계정 행.
private struct Row: AiCliAccountIdentifiable, Sendable, Equatable {
    let id: UUID
    let identityClient: AiCliClient
    let identityKind: AiCliAccountKind
    let identitySessionKey: String?

    init(
        id: UUID = UUID(),
        _ client: AiCliClient,
        key: String?,
        kind: AiCliAccountKind = .oauthSession
    ) {
        self.id = id
        self.identityClient = client
        self.identityKind = kind
        self.identitySessionKey = key
    }
}

final class AccountIdentityTests: XCTestCase {
    func testKeylessAccountHasNoIdentity() {
        XCTAssertNil(AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: nil))
        XCTAssertNil(AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: ""))
        XCTAssertNil(AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: "   "))
    }

    func testIdentityIgnoresSurroundingWhitespace() {
        let a = AccountIdentity(client: .codex, kind: .oauthSession, sessionKey: " team@example.com ")
        let b = AccountIdentity(client: .codex, kind: .oauthSession, sessionKey: "team@example.com")
        XCTAssertEqual(a, b)
    }

    func testIdentitySeparatesClientAndKind() {
        let key = "org-uuid"
        XCTAssertNotEqual(
            AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: key),
            AccountIdentity(client: .codex, kind: .oauthSession, sessionKey: key)
        )
        XCTAssertNotEqual(
            AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: key),
            AccountIdentity(client: .claudeCode, kind: .backendProfile, sessionKey: key)
        )
    }

    // MARK: - decide

    func testDecideUpdatesExistingAccount() {
        let existing = Row(.claudeCode, key: "org-a")
        let decision = AccountIdentity.decide(
            accounts: [Row(.codex, key: "x"), existing],
            client: .claudeCode,
            sessionKey: "org-a"
        )
        guard case .update(let hit) = decision else { return XCTFail("expected update, got \(decision)") }
        XCTAssertEqual(hit, existing)
    }

    func testDecideCreatesWhenUnseen() {
        let decision = AccountIdentity.decide(
            accounts: [Row(.claudeCode, key: "org-a")],
            client: .claudeCode,
            sessionKey: "org-b"
        )
        guard case .create(let identity) = decision else { return XCTFail("expected create, got \(decision)") }
        XCTAssertEqual(identity.sessionKey, "org-b")
    }

    /// 중복 행 폭증 버그의 회귀 방지: 키가 없으면 새 계정을 만들지 않는다.
    /// 예전에는 이 경로가 `create` 로 떨어져 새로고침마다 행이 하나씩 늘었다.
    func testDecideSkipsWhenSessionKeyMissing() {
        for key in [nil, "", "  "] as [String?] {
            let decision = AccountIdentity.decide(
                accounts: [Row(.claudeCode, key: nil)],
                client: .claudeCode,
                sessionKey: key
            )
            guard case .skip(let reason) = decision else {
                return XCTFail("expected skip for \(String(describing: key)), got \(decision)")
            }
            XCTAssertEqual(reason, .unidentifiableSession)
        }
    }

    /// 같은 캡처를 여러 번 반영해도 목록이 자라지 않는다(새로고침 반복 시나리오).
    func testRepeatedDecisionsNeverGrowTheList() {
        var accounts = [Row]()
        for _ in 0..<10 {
            switch AccountIdentity.decide(accounts: accounts, client: .claudeCode, sessionKey: "org-a") {
            case .create: accounts.append(Row(.claudeCode, key: "org-a"))
            case .update, .skip: break
            }
        }
        XCTAssertEqual(accounts.count, 1)

        // 키를 못 뽑는 클라이언트도 마찬가지로 한 행도 만들지 않는다.
        var keyless = [Row]()
        for _ in 0..<10 {
            switch AccountIdentity.decide(accounts: keyless, client: .grok, sessionKey: nil) {
            case .create: keyless.append(Row(.grok, key: nil))
            case .update, .skip: break
            }
        }
        XCTAssertTrue(keyless.isEmpty)
    }

    // MARK: - find / canImport

    func testFindNeverMatchesOnMissingKey() {
        let accounts = [Row(.claudeCode, key: nil), Row(.claudeCode, key: nil)]
        XCTAssertNil(AccountIdentity.find(in: accounts, client: .claudeCode, sessionKey: nil))
    }

    func testCanImportIsFalseWithoutActiveKey() {
        XCTAssertFalse(
            AccountIdentity.canImport(client: .gemini, activeSessionKey: nil, accounts: [Row]())
        )
    }

    func testCanImportIsFalseWhenAlreadyStored() {
        XCTAssertFalse(
            AccountIdentity.canImport(
                client: .codex,
                activeSessionKey: "team@example.com",
                accounts: [Row(.codex, key: "team@example.com")]
            )
        )
    }

    func testCanImportIsTrueForNewIdentifiableSession() {
        XCTAssertTrue(
            AccountIdentity.canImport(
                client: .codex,
                activeSessionKey: "new@example.com",
                accounts: [Row(.codex, key: "team@example.com")]
            )
        )
    }

    // MARK: - grouping

    func testGroupedByIdentityCollapsesDuplicatesAndDropsKeyless() {
        let rows = [
            Row(.claudeCode, key: "org-a"),
            Row(.claudeCode, key: "org-a"),
            Row(.claudeCode, key: "org-b"),
            Row(.claudeCode, key: nil),
        ]
        let groups = rows.groupedByIdentity()
        XCTAssertEqual(groups.count, 2)
        let orgA = AccountIdentity(client: .claudeCode, kind: .oauthSession, sessionKey: "org-a")
        XCTAssertEqual(groups[orgA!]?.count, 2)
    }
}
