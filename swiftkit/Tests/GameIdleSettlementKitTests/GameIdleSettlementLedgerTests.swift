import Foundation
import Testing
@testable import GameIdleSettlementKit

@Suite("정산 원장 — 재정산 방지와 단조 누적")
struct GameIdleSettlementLedgerTests {
    private let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func ledger() -> GameIdleSettlementLedger {
        GameIdleSettlementLedger(lastSettledAt: base)
    }

    @Test("정산한 초만큼만 기준선이 전진한다(1초 미만 잔여는 남는다)")
    func baselineAdvancesByConsumedSeconds() {
        var ledger = ledger()
        let outcome = ledger.consume(
            now: base.addingTimeInterval(90.5),
            policy: .standardV1
        )
        #expect(outcome.settledSeconds == 90)
        #expect(ledger.lastSettledAt == base.addingTimeInterval(90))
        #expect(ledger.monotonicPlayedSeconds == 90)
        #expect(ledger.settlementCount == 1)
    }

    @Test("같은 구간을 두 번 요청해도 두 번째는 지급되지 않는다")
    func doubleSettlementIsBlocked() {
        var ledger = ledger()
        let now = base.addingTimeInterval(3600)
        #expect(ledger.consume(now: now, policy: .standardV1).settledSeconds == 3600)
        let second = ledger.consume(now: now, policy: .standardV1)
        #expect(second.settledSeconds == 0)
        #expect(second.isEmpty)
        #expect(ledger.monotonicPlayedSeconds == 3600)
        #expect(ledger.settlementCount == 2)
    }

    @Test("두 번째 정산은 이전 정산 이후 구간만 지급한다")
    func secondSettlementOnlyGetsNewInterval() {
        var ledger = ledger()
        _ = ledger.consume(now: base.addingTimeInterval(3600), policy: .standardV1)
        let second = ledger.consume(now: base.addingTimeInterval(3610), policy: .standardV1)
        #expect(second.settledSeconds == 10)
        #expect(ledger.monotonicPlayedSeconds == 3610)
    }

    @Test("미리보기는 원장을 바꾸지 않는다")
    func previewIsPure() {
        var ledger = ledger()
        let now = base.addingTimeInterval(120)
        #expect(ledger.preview(now: now, policy: .standardV1).settledSeconds == 120)
        #expect(ledger.lastSettledAt == base)
        #expect(ledger.settlementCount == 0)
        #expect(ledger.consume(now: now, policy: .standardV1).settledSeconds == 120)
    }

    @Test("최소 임계 미만은 기본적으로 이월된다")
    func belowMinimumCarriesOver() {
        var ledger = ledger()
        let first = ledger.consume(
            now: base.addingTimeInterval(30),
            policy: .shortSessionV1
        )
        #expect(first.settledSeconds == 0)
        #expect(first.wasBelowMinimum)
        #expect(ledger.lastSettledAt == base)

        let second = ledger.consume(
            now: base.addingTimeInterval(70),
            policy: .shortSessionV1
        )
        #expect(second.settledSeconds == 70)
        #expect(ledger.monotonicPlayedSeconds == 70)
    }

    @Test("최소 임계 미만 폐기 정책은 기준선을 현재로 당긴다")
    func belowMinimumDiscards() throws {
        let policy = try GameIdleElapsedPolicy(
            minimumSeconds: 60,
            maximumSeconds: 28_800,
            overflow: .discard,
            belowMinimum: .discard
        )
        var ledger = ledger()
        let now = base.addingTimeInterval(30)
        #expect(ledger.consume(now: now, policy: policy).settledSeconds == 0)
        #expect(ledger.lastSettledAt == now)
        #expect(ledger.consume(now: base.addingTimeInterval(70), policy: policy).settledSeconds == 0)
    }

    @Test("캡 초과분은 폐기 정책에서 사라진다")
    func cappedOverflowDiscarded() {
        var ledger = ledger()
        let now = base.addingTimeInterval(30 * 86_400)
        let outcome = ledger.consume(now: now, policy: .standardV1)
        #expect(outcome.settledSeconds == 604_800)
        #expect(outcome.wasCapped)
        #expect(ledger.lastSettledAt == now)
        #expect(ledger.consume(now: now, policy: .standardV1).settledSeconds == 0)
    }

    @Test("캡 초과분 이월 정책은 다음 정산으로 넘긴다")
    func cappedOverflowBanked() throws {
        let policy = try GameIdleElapsedPolicy(
            maximumSeconds: 7 * 86_400,
            overflow: .bank
        )
        var ledger = ledger()
        let now = base.addingTimeInterval(30 * 86_400)
        #expect(ledger.consume(now: now, policy: policy).settledSeconds == 604_800)
        #expect(ledger.lastSettledAt == base.addingTimeInterval(604_800))
        #expect(ledger.consume(now: now, policy: policy).settledSeconds == 604_800)
        #expect(ledger.monotonicPlayedSeconds == 1_209_600)
    }

    @Test("시계 역행은 0 정산 + 기준선 리셋으로 복구한다")
    func backwardsClockResetsBaseline() {
        var ledger = ledger()
        let now = base.addingTimeInterval(-86_400)
        let outcome = ledger.consume(now: now, policy: .standardV1)
        #expect(outcome.settledSeconds == 0)
        #expect(outcome.clockWentBackwards)
        #expect(ledger.lastSettledAt == now)
        #expect(ledger.monotonicPlayedSeconds == 0)
    }

    @Test("단조 누적은 시계를 되돌려도 줄지 않는다")
    func monotonicNeverDecreases() {
        var ledger = ledger()
        _ = ledger.consume(now: base.addingTimeInterval(600), policy: .standardV1)
        let afterFirst = ledger.monotonicPlayedSeconds
        #expect(afterFirst == 600)

        _ = ledger.consume(now: base.addingTimeInterval(-100_000), policy: .standardV1)
        #expect(ledger.monotonicPlayedSeconds == afterFirst)

        _ = ledger.consume(now: base.addingTimeInterval(-99_500), policy: .standardV1)
        #expect(ledger.monotonicPlayedSeconds == afterFirst + 500)
    }

    @Test("온라인 진행분도 단조 누적에 들어간다")
    func creditOnline() {
        var ledger = ledger()
        ledger.creditOnline(seconds: 10)
        ledger.creditOnline(seconds: 0)
        ledger.creditOnline(seconds: -5)
        #expect(ledger.monotonicPlayedSeconds == 10)

        let saveTime = base.addingTimeInterval(45)
        ledger.creditOnline(seconds: 35, now: saveTime)
        #expect(ledger.monotonicPlayedSeconds == 45)
        #expect(ledger.lastSettledAt == saveTime)
        #expect(ledger.consume(now: saveTime, policy: .standardV1).settledSeconds == 0)
    }

    @Test("단조 누적은 Int 를 넘기지 않고 포화한다")
    func monotonicSaturates() {
        var ledger = GameIdleSettlementLedger(
            lastSettledAt: base,
            monotonicPlayedSeconds: Int.max - 5
        )
        ledger.creditOnline(seconds: 100)
        #expect(ledger.monotonicPlayedSeconds == Int.max)

        var huge = GameIdleSettlementLedger(
            lastSettledAt: Date(timeIntervalSinceReferenceDate: 0),
            monotonicPlayedSeconds: Int.max - 5
        )
        _ = huge.consume(now: Date(timeIntervalSinceReferenceDate: 1e300), policy: .standardV1)
        #expect(huge.monotonicPlayedSeconds == Int.max)
    }

    @Test("음수 입력은 생성에서 접힌다")
    func initClamps() {
        let ledger = GameIdleSettlementLedger(
            lastSettledAt: base,
            monotonicPlayedSeconds: -10,
            settlementCount: -3
        )
        #expect(ledger.monotonicPlayedSeconds == 0)
        #expect(ledger.settlementCount == 0)
    }

    @Test("무한대 기준선은 저장 가능한 시각으로 접힌다")
    func nonFiniteBaseline() {
        let ledger = GameIdleSettlementLedger(
            lastSettledAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        #expect(GameIdleSeconds.isFinite(ledger.lastSettledAt))

        var moved = GameIdleSettlementLedger(lastSettledAt: base)
        moved.advanceBaseline(to: Date(timeIntervalSinceReferenceDate: .infinity))
        #expect(moved.lastSettledAt == base)
    }

    @Test("원장은 저장에 그대로 실린다")
    func codable() throws {
        var ledger = ledger()
        _ = ledger.consume(now: base.addingTimeInterval(120), policy: .standardV1)
        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(GameIdleSettlementLedger.self, from: data)
        #expect(restored == ledger)
        #expect(restored.monotonicPlayedSeconds == 120)
    }

    @Test("저장이 없어도 원장이 전진했으면 재정산되지 않는다")
    func crashAfterSettlementDoesNotDoublePay() {
        // 정산 → 저장 실패 → 같은 세션에서 재시도, 를 재현한다.
        var ledger = ledger()
        let now = base.addingTimeInterval(7200)
        #expect(ledger.consume(now: now, policy: .standardV1).settledSeconds == 7200)
        let retried = ledger.consume(now: now, policy: .standardV1)
        #expect(retried.settledSeconds == 0)

        // 반대로 저장된 원장을 다시 읽어 들이면 디스크 기준선이 그대로 이어진다.
        let reloaded = GameIdleSettlementLedger(
            lastSettledAt: ledger.lastSettledAt,
            monotonicPlayedSeconds: ledger.monotonicPlayedSeconds
        )
        var next = reloaded
        #expect(next.consume(now: now, policy: .standardV1).settledSeconds == 0)
    }
}
