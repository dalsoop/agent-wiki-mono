import Foundation
import Testing
@testable import VaultwardenKit

/// keychain-doctor probe 계약 — 항목 존재·쓰기권한을 단계별 OSStatus 로 드러낸다.
/// 값은 읽지·쓰지 않는다(comment 도장 제외) — 진단이 비밀을 유출하는 경로가 되면 안 된다.
@Suite("키체인 진단 probe")
struct KeychainStoreProbeTests {
    /// 스크래치 항목 — 같은 바이너리가 만들었으니 조회·갱신 모두 성공해야 한다.
    @Test func probeReportsSuccessForOwnItem() throws {
        let store = KeychainStore(service: "net.ranode.vaultwarden-kit.tests.scratch")
        let account = "probe-\(UUID().uuidString.prefix(8))"
        defer { store.delete(account: account) }
        try store.set(Data("value".utf8), account: account)

        let probe = store.probe(account: account)
        #expect(probe.account == account)
        #expect(probe.find == 0)
        #expect(probe.readData == 0)
        #expect(probe.updateAttribute == 0)
    }

    /// 없는 항목 — find 가 itemNotFound(-25300) 로 보고되고 읽기·갱신도 같은 상태여야 한다.
    @Test func probeReportsMissingItem() {
        let store = KeychainStore(service: "net.ranode.vaultwarden-kit.tests.scratch")

        let probe = store.probe(account: "probe-missing-\(UUID().uuidString.prefix(8))")
        #expect(probe.find == Int(errSecItemNotFound))
        #expect(probe.readData == Int(errSecItemNotFound))
        #expect(probe.updateAttribute == Int(errSecItemNotFound))
    }

    /// probe 는 값을 바꾸지 않는다 — comment 도장만 찍힌다.
    @Test func probeDoesNotTouchValue() throws {
        let store = KeychainStore(service: "net.ranode.vaultwarden-kit.tests.scratch")
        let account = "probe-value-\(UUID().uuidString.prefix(8))"
        defer { store.delete(account: account) }
        try store.set(Data("secret-stays".utf8), account: account)

        _ = store.probe(account: account)

        #expect(store.get(account: account) == Data("secret-stays".utf8))
    }
}
