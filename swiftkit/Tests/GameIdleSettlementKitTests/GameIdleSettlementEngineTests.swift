import Foundation
import Testing
@testable import GameIdleSettlementKit

@Suite("정산 엔진 — 게임별 페이로드")
struct GameIdleSettlementEngineTests {
    private let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private struct ResourceDelta: Codable, Hashable, Sendable {
        var gold: Int
        var food: Int
    }

    private enum CreditFailure: Error, Equatable { case rejected }

    @Test("gaya 식 Int 페이로드")
    func integerPayload() {
        let engine = GameIdleSettlementEngine<Int>(policy: .shortSessionV1)
        var ledger = GameIdleSettlementLedger(lastSettledAt: base)
        let now = base.addingTimeInterval(2 * 3600)
        let report = engine.settle(ledger: &ledger, now: now) { seconds in
            seconds * 3
        }
        #expect(report.payload == 21_600)
        #expect(report.settledSeconds == 7_200)
        #expect(report.occurredAt == now)
        #expect(report.baselineAfterSettlement == now)
        #expect(report.monotonicPlayedSeconds == 7_200)
        #expect(!report.isEmpty)
        #expect(report.duration.hours == 2)
        #expect(report.duration.days == 0)
    }

    @Test("isekai 식 구조체 페이로드")
    func structPayload() throws {
        let engine = GameIdleSettlementEngine<ResourceDelta>()
        var ledger = GameIdleSettlementLedger(lastSettledAt: base)
        let report = engine.settle(
            ledger: &ledger,
            now: base.addingTimeInterval(90_061)
        ) { seconds in
            ResourceDelta(gold: seconds * 2, food: -seconds)
        }
        #expect(report.payload == ResourceDelta(gold: 180_122, food: -90_061))
        #expect(report.duration.days == 1)
        #expect(report.duration.hours == 1)

        let data = try JSONEncoder().encode(report)
        let restored = try JSONDecoder().decode(
            GameIdleSettlementReport<ResourceDelta>.self,
            from: data
        )
        #expect(restored == report)
    }

    @Test("0초 정산도 페이로드를 만들되 비어 있다고 표시한다")
    func emptySettlement() {
        let engine = GameIdleSettlementEngine<Int>(policy: .shortSessionV1)
        var ledger = GameIdleSettlementLedger(lastSettledAt: base)
        var creditedSeconds: [Int] = []
        let report = engine.settle(ledger: &ledger, now: base.addingTimeInterval(10)) {
            creditedSeconds.append($0)
            return $0
        }
        #expect(creditedSeconds == [0])
        #expect(report.isEmpty)
        #expect(report.elapsed.wasBelowMinimum)
        #expect(ledger.lastSettledAt == base)
    }

    @Test("credit 이 던지면 원장은 그대로 남는다")
    func creditFailureLeavesLedgerUntouched() {
        let engine = GameIdleSettlementEngine<Int>()
        var ledger = GameIdleSettlementLedger(lastSettledAt: base)
        #expect(throws: CreditFailure.rejected) {
            try engine.settle(ledger: &ledger, now: base.addingTimeInterval(600)) { _ in
                throw CreditFailure.rejected
            }
        }
        #expect(ledger.lastSettledAt == base)
        #expect(ledger.monotonicPlayedSeconds == 0)
        #expect(ledger.settlementCount == 0)

        // 실패 후 다시 시도하면 같은 구간을 온전히 받는다.
        let report = engine.settle(ledger: &ledger, now: base.addingTimeInterval(600)) { $0 }
        #expect(report.settledSeconds == 600)
    }

    @Test("주입된 벽시계로 정산한다")
    func settleWithInjectedClock() {
        let clock = ManualGameIdleWallClock(now: base)
        let engine = GameIdleSettlementEngine<Int>()
        var ledger = GameIdleSettlementLedger(lastSettledAt: base)

        clock.advance(by: 300)
        #expect(engine.settle(ledger: &ledger, clock: clock) { $0 }.settledSeconds == 300)

        // 시계 역행 재현.
        clock.advance(by: -1000)
        let backwards = engine.settle(ledger: &ledger, clock: clock) { $0 }
        #expect(backwards.settledSeconds == 0)
        #expect(backwards.elapsed.clockWentBackwards)
        #expect(ledger.monotonicPlayedSeconds == 300)
    }

    @Test("시스템 벽시계는 현재 시각을 준다")
    func systemClock() {
        let clock = SystemGameIdleWallClock()
        #expect(abs(clock.now().timeIntervalSinceNow) < 5)
    }
}
