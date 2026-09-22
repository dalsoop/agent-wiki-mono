import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerModels

final class ContentHashTests: XCTestCase {
    /// 해시 문자열은 저장 계약이다 — 이 벡터가 깨지면 기존 원장 전체가 재유입된다.
    /// 알고리즘을 바꿔야 하면 버전 접두사(mf1)를 올리고 마이그레이션을 설계할 것.
    func testStableVector() {
        let hash = ContentHash.transactionHash(
            date: "2026-08-04",
            time: "13:22:01",
            amountMinor: -15000,
            currency: "KRW",
            instrumentID: "acct-1",
            description: "스타벅스 강남점",
            balanceAfterMinor: 1_000_000,
            occurrence: 1
        )
        XCTAssertEqual(hash.count, 64)
        // 같은 입력 = 같은 해시 (재가져오기 멱등성의 근거)
        let again = ContentHash.transactionHash(
            date: "2026-08-04",
            time: "13:22:01",
            amountMinor: -15000,
            currency: "KRW",
            instrumentID: "acct-1",
            description: "스타벅스 강남점",
            balanceAfterMinor: 1_000_000,
            occurrence: 1
        )
        XCTAssertEqual(hash, again)
    }

    func testOccurrenceChangesHash() {
        func hash(occurrence: Int) -> String {
            ContentHash.transactionHash(
                date: "2026-08-04", time: nil, amountMinor: -5000, currency: "KRW",
                instrumentID: "a", description: "커피", balanceAfterMinor: nil, occurrence: occurrence
            )
        }
        XCTAssertNotEqual(hash(occurrence: 1), hash(occurrence: 2))
    }

    func testDescriptionNormalization() {
        XCTAssertEqual(ContentHash.normalizedDescription("  스타벅스   강남점  "), "스타벅스 강남점")
        XCTAssertEqual(ContentHash.normalizedDescription("a\t b\n c"), "a b c")
        // NFC 정규화 — 조합형(NFD) 한글도 같은 해시로.
        let nfd = "스타벅스".decomposedStringWithCanonicalMapping
        XCTAssertEqual(ContentHash.normalizedDescription(nfd), "스타벅스")
    }

    func testInstrumentSeparation() {
        func hash(instrument: String) -> String {
            ContentHash.transactionHash(
                date: "2026-08-04", time: nil, amountMinor: -5000, currency: "KRW",
                instrumentID: instrument, description: "커피", balanceAfterMinor: nil
            )
        }
        XCTAssertNotEqual(hash(instrument: "acct-1"), hash(instrument: "acct-2"))
    }
}
