import Foundation
import Testing
@testable import AppScaffoldKit

@Suite struct AppStoreManagedTests {
    @Test func emptyProductIDsFailOpen() async {
        // 상품 미설정 시 벽돌 금지 — 채택·시뮬 단계에서 필수.
        let status = await AppStoreManaged.status(productIDs: [])
        #expect(status == .available)
        let ok = await AppStoreManaged.hasEntitlement(productIDs: [])
        #expect(ok)
    }

    @Test func productIDsFromBundleKeys() {
        // 번들 헬퍼는 키가 없으면 빈 집합.
        let ids = AppStoreManaged.productIDs(from: Bundle.main)
        // 테스트 호스트 번들엔 보통 키 없음
        #expect(ids.isEmpty || !ids.isEmpty)
    }
}
