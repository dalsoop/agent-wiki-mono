import XCTest
import MoneyLedgerModels

/// 구독 한 건이 답해야 하는 네 축을 고정한다 — 어느 카드로 빠지나(결제수단),
/// 누구 경비인가(사업체), 어느 앱이 만든 행인가(외부 링크), 언제 얼마로 오르나(프로모).
/// 넷 다 없으면 원장이 "월 15,000원" 이라는 사실 하나만 알고 나머지는 사람 머리에 남는다.
final class SubscriptionAxesTests: XCTestCase {
    func testExternalKeyRequiresBothHalves() {
        var sub = MoneySubscription(name: "Claude", amountMinor: 20_000)
        XCTAssertNil(sub.externalKey, "링크가 없으면 키도 없다")

        sub.sourceApp = "ai-cli-account-manager"
        XCTAssertNil(sub.externalKey, "한쪽만으로는 동일성을 못 세운다")

        sub.externalID = "7d7a210e-57c4-4d0b-b79c-4008a11c3215"
        XCTAssertEqual(
            sub.externalKey,
            "ai-cli-account-manager#7d7a210e-57c4-4d0b-b79c-4008a11c3215"
        )
    }

    func testFourAxesSurviveEncodeDecode() throws {
        let original = MoneySubscription(
            name: "SuperGrok Heavy",
            amount: .init(amountMinor: 3_300, currency: "USD"),
            billing: .init(
                nextBillingDate: "2026-09-09",
                promoEndsOn: "2026-09-08",
                regularAmountMinor: 30_000
            ),
            links: .init(
                paymentCardID: "card-1",
                businessID: "biz-dalsoop",
                sourceApp: "ai-cli-account-manager",
                externalID: "c086f4e6"
            )
        )

        // 저장은 payload BLOB 이라 새 필드가 마이그레이션 없이 실린다 —
        // 그 전제가 깨지면 여기서 먼저 터진다.
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(MoneySubscription.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.businessID, "biz-dalsoop")
        XCTAssertEqual(restored.promoEndsOn, "2026-09-08")
        XCTAssertEqual(restored.regularAmountMinor, 30_000)
    }

    func testOldRecordsWithoutNewAxesStillDecode() throws {
        // 이미 저장된 행에는 새 키가 없다. 옵셔널이라 nil 로 열려야 한다.
        let legacy = """
        {"id":"abc","name":"Netflix","amountMinor":13500,"currency":"KRW",
         "period":"monthly","status":"active","archived":false,
         "createdAt":768000000}
        """
        let sub = try JSONDecoder().decode(MoneySubscription.self, from: Data(legacy.utf8))
        XCTAssertEqual(sub.name, "Netflix")
        XCTAssertNil(sub.businessID)
        XCTAssertNil(sub.sourceApp)
        XCTAssertNil(sub.promoEndsOn)
        XCTAssertNil(sub.regularAmountMinor)
        XCTAssertNil(sub.externalKey)
    }

    func testPromoCliffIsRepresentable() {
        // $33/월 로 보이다가 프로모가 끝나면 $300/월 이 되는 절벽.
        // 지금 금액만 저장하면 원장이 이 사실을 예고하지 못한다.
        let sub = MoneySubscription(
            name: "SuperGrok Heavy",
            amount: .init(amountMinor: 3_300, currency: "USD"),
            billing: .init(promoEndsOn: "2026-09-08", regularAmountMinor: 30_000)
        )
        XCTAssertEqual(sub.amountMinor, 3_300)
        XCTAssertEqual(sub.regularAmountMinor, 30_000)
        XCTAssertNotNil(sub.promoEndsOn)
    }
}
