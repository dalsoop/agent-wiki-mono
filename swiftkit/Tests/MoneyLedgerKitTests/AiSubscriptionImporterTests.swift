import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerImportKit

/// 브리지는 **관측값을 돈으로 옮기는 지점**이라 조용히 틀리면 원장이 거짓말을 한다.
/// 그래서 계약 미달을 때우지 않고 멈추는지, 금액이 정확히 최소단위로 떨어지는지를 고정한다.
final class AiSubscriptionImporterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)  // 고정 기준일

    private func payload(_ rows: String) -> String {
        """
        {"ok":true,"result":{"probedAt":"2026-08-10T00:00:00Z","rows":[\(rows)]}}
        """
    }

    func testParsesPricedRowIntoMinorUnits() throws {
        let rows = try AiSubscriptionImporter.parse(
            payload("""
            {"id":"7d7a210e","client":"claudeCode","label":"team@dalsoop.com",
             "plan":"Max 20x","monthlyAmount":200,"currency":"USD",
             "renewsAt":"2026-08-27T05:45:01Z","daysUntil":17}
            """),
            now: now
        )
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.monthlyMinor, 20_000, "USD 200 = 20000 최소단위")
        XCTAssertEqual(row.currency, "USD")
        XCTAssertEqual(row.nextBillingDate, "2026-08-27", "ISO 타임스탬프에서 날짜만")
        XCTAssertEqual(row.displayName, "Max 20x (claudeCode)")
        XCTAssertNil(row.promoEndsOn)
    }

    func testPromoCliffCarriesEndDateAndRegularPrice() throws {
        let rows = try AiSubscriptionImporter.parse(
            payload("""
            {"id":"e33f399c","client":"grok","label":"dalsoop","plan":"SuperGrok Heavy",
             "monthlyAmount":33,"postPromoMonthlyAmount":300,"currency":"USD",
             "promoEndsInDays":30,"renewsAt":"2026-09-09T00:00:00Z","daysUntil":30}
            """),
            now: now
        )
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.monthlyMinor, 3_300)
        XCTAssertEqual(row.regularMinor, 30_000, "프로모 종료 후 정가가 실려야 절벽을 예고한다")
        XCTAssertEqual(row.promoEndsOn, LedgerDate.format(now.addingTimeInterval(30 * 86_400)))
    }

    func testStaleCliContractFailsLoudlyInsteadOfGuessing() {
        // 낡은 CLI 는 "Max 20x · $200/월" 문자열만 준다. 그걸 파싱해 때우면
        // 조용히 틀린 금액이 원장에 박힌다 — 멈추는 게 맞다.
        let stale = payload("""
        {"id":"7d7a210e","client":"claudeCode","label":"team@dalsoop.com",
         "plan":"Max 20x","deal":"Max 20x · $200/월","daysUntil":17,
         "renewsAt":"2026-08-27T05:45:01Z"}
        """)
        XCTAssertThrowsError(try AiSubscriptionImporter.parse(stale, now: now)) { error in
            guard case AiSubscriptionImporter.ImportError.contractTooOld = error else {
                return XCTFail("계약 미달로 판정해야 한다: \(error)")
            }
        }
    }

    func testUnpricedRowIsSkippedWhenOthersArePriced() throws {
        // 일부만 가격을 모르는 건 정상이다(ACM 이 unpricedRowCount 로 센다).
        let mixed = payload("""
        {"id":"a","client":"codex","label":"x","monthlyAmount":20,"currency":"USD",
         "renewsAt":"2026-09-07T11:16:13Z","daysUntil":28},
        {"id":"b","client":"gemini","label":"y","renewsAt":"2026-09-01T00:00:00Z","daysUntil":22}
        """)
        let rows = try AiSubscriptionImporter.parse(mixed, now: now)
        XCTAssertEqual(rows.count, 1, "가격 없는 행만 빠진다")
        XCTAssertEqual(rows.first?.externalID, "a")
    }

    func testErrorEnvelopeSurfacesMessage() {
        let failure = #"{"ok":false,"error":{"message":"계정 없음"}}"#
        XCTAssertThrowsError(try AiSubscriptionImporter.parse(failure, now: now)) { error in
            guard case AiSubscriptionImporter.ImportError.cliFailed(let message) = error else {
                return XCTFail("cliFailed 여야 한다: \(error)")
            }
            XCTAssertEqual(message, "계정 없음")
        }
    }

    func testBareObjectFromOlderEnvelopeStillParses() throws {
        // 봉투 이전 판(맨 객체)도 받는다 — 설치본 갱신 시점이 앱마다 다르다.
        let bare = """
        {"rows":[{"id":"a","client":"codex","label":"x","monthlyAmount":20,
                  "currency":"USD","renewsAt":"2026-09-07T11:16:13Z"}]}
        """
        XCTAssertEqual(try AiSubscriptionImporter.parse(bare, now: now).count, 1)
    }
}
