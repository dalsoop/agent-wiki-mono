import XCTest
@testable import KeychainKit

final class CachedKeychainStoreTests: XCTestCase {
    private func store() -> CachedKeychainStore {
        // 테스트마다 고유 service 로 실제 Keychain 을 격리해 쓰고 tearDown 에서 지운다.
        CachedKeychainStore(service: "test.keychainkit.\(UUID().uuidString)")
    }

    func testSetGetRoundTrip() {
        let s = store()
        defer { s.delete(account: "a") }
        XCTAssertNil(s.string(account: "a"))
        s.set("secret", account: "a")
        XCTAssertEqual(s.string(account: "a"), "secret")
        XCTAssertTrue(s.has(account: "a"))
    }

    func testDeleteReflectedThroughCache() {
        let s = store()
        s.set("v", account: "a")
        XCTAssertTrue(s.has(account: "a"))
        s.delete(account: "a")
        XCTAssertFalse(s.has(account: "a"))   // 캐시가 삭제를 반영(재조회 없이)
        XCTAssertNil(s.string(account: "a"))
    }

    func testAbsentIsCachedAndStable() {
        let s = store()
        XCTAssertFalse(s.has(account: "missing"))
        XCTAssertFalse(s.has(account: "missing"))   // 없음도 캐시 — 반복 조회 안정
    }

    func testSetUpdatesCachedValue() {
        let s = store()
        defer { s.delete(account: "a") }
        s.set("one", account: "a")
        XCTAssertEqual(s.string(account: "a"), "one")
        s.set("two", account: "a")
        XCTAssertEqual(s.string(account: "a"), "two")   // 쓰기가 캐시를 새 값으로 갱신
    }

    /// 짧은 timeout 이어도 전용 큐 + 동기 SecItem 경로면 일반 항목은 읽힌다.
    /// (예전 global.async+sem 패턴은 환경에 따라 항상 timedOut 오탐.)
    func testReadWithTimeoutStillReturnsValue() {
        let service = "test.keychainkit.timeout.\(UUID().uuidString)"
        let s = CachedKeychainStore(service: service, readTimeout: 2.5)
        defer { s.delete(account: "a") }
        s.set("ok", account: "a")
        s.invalidate(account: "a")
        XCTAssertEqual(s.string(account: "a"), "ok")
        XCTAssertFalse(s.lastReadTimedOut)
    }

    func testListAccounts() {
        let service = "test.keychainkit.list.\(UUID().uuidString)"
        let s = CachedKeychainStore(service: service, readTimeout: 0)
        defer {
            s.delete(account: "p1")
            s.delete(account: "p2")
        }
        s.set("a", account: "p1")
        s.set("b", account: "p2")
        XCTAssertEqual(s.listAccounts(), ["p1", "p2"])
    }

    /// trusted ACL 이 있어도 현재 프로세스 쓰기는 성공한다 (관제 dual-entry 패턴).
    func testTrustedAccessWriteRoundTrip() {
        let service = "test.keychainkit.acl.\(UUID().uuidString)"
        let policy = KeychainTrustedAccess(label: "KeychainKit test ACL")
        let s = CachedKeychainStore(
            service: service,
            readTimeout: 0,
            trustedAccess: policy)
        defer { s.delete(account: "a") }
        s.set("with-acl", account: "a")
        XCTAssertEqual(s.string(account: "a"), "with-acl")
    }

    func testDualEntryPolicyBuildsPathsWhenBundleExists() {
        let app = "/Applications/AgentVault.app"
        let helper = "/Applications/AgentVault.app/Contents/Helpers/agent-vault"
        let policy = KeychainTrustedAccess.dualEntryControlPlane(
            appBundlePath: app, helperCLIPath: helper)
        XCTAssertEqual(policy.label, "AgentVault control plane")
        // 설치본이 있으면 helper 경로가 포함된다. 없으면 빈 배열일 수 있음.
        if FileManager.default.isExecutableFile(atPath: helper) {
            XCTAssertTrue(policy.applicationPaths.contains(helper))
        }
    }
}
