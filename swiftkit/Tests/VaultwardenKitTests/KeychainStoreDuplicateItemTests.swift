import Foundation
import Testing
@testable import VaultwardenKit

/// 재설치 키체인 자가치유 계약 — 2026-08-23 실측 사고.
///
/// 앱 재설치로 바이너리(cdhash)가 바뀌면 옛 항목의 ACL 이 옛 바이너리만 신뢰해서
/// `SecItemDelete` 가 몰래 실패하고 `SecItemAdd` 가 `errSecDuplicateItem`(-25299) 으로
/// 죽었다("keychain error" 재로그인 막다길). `set` 은 이 상태에서 `SecItemUpdate`
/// 폴백으로 갈아타야 한다 — 폴백 판정은 상태 하나로 결정되는 순수 함수다.
@Suite("키체인 중복 항목 폴백")
struct KeychainStoreDuplicateItemTests {
    @Test func duplicateItemStatusTriggersUpdateFallback() {
        #expect(KeychainStore.shouldFallbackToUpdate(errSecDuplicateItem))
    }

    @Test func otherStatusesPassThroughUnchanged() {
        // -25300 interactionNotAllowed · -25293 authFailed · 0 성공 등 그 외 상태는
        // 폴백 대상이 아니다 — 잘못 폴백하면 진짜 실패 원인이 묻힌다.
        #expect(!KeychainStore.shouldFallbackToUpdate(errSecInteractionNotAllowed))
        #expect(!KeychainStore.shouldFallbackToUpdate(errSecAuthFailed))
        #expect(!KeychainStore.shouldFallbackToUpdate(errSecSuccess))
        #expect(!KeychainStore.shouldFallbackToUpdate(errSecItemNotFound))
    }

    /// 같은 바이너리가 두 번 쓰는 정상 경로(삭제→추가)는 폴백이 없어도 멱등해야 한다.
    /// 스크래치 서비스에 쓰고 지운다 — 다른 항목을 건드리지 않는다.
    @Test func setOverwritesIdempotentlyOnScratchService() throws {
        let store = KeychainStore(service: "net.ranode.vaultwarden-kit.tests.scratch")
        let account = "duplicate-fallback-\(UUID().uuidString.prefix(8))"
        defer { store.delete(account: account) }

        try store.set(Data("first".utf8), account: account)
        try store.set(Data("second".utf8), account: account)

        #expect(store.get(account: account) == Data("second".utf8))
    }
}
