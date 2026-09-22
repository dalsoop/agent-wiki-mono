import Foundation
import Testing
@testable import GameIdleSettlementKit

@Suite("오프라인 경과 산출 정책")
struct GameIdleElapsedPolicyTests {
    private let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("프리셋 값은 두 선행 구현의 실측값과 같다")
    func presets() {
        #expect(GameIdleElapsedPolicy.standardV1.minimumSeconds == 0)
        #expect(GameIdleElapsedPolicy.standardV1.maximumSeconds == 604_800)
        #expect(GameIdleElapsedPolicy.standardV1.overflow == .discard)
        #expect(GameIdleElapsedPolicy.shortSessionV1.minimumSeconds == 60)
        #expect(GameIdleElapsedPolicy.shortSessionV1.maximumSeconds == 28_800)
    }

    @Test("잘못된 설정은 생성에서 막힌다")
    func validation() throws {
        #expect(throws: GameIdleElapsedPolicyError.negativeMinimumSeconds(-1)) {
            try GameIdleElapsedPolicy(minimumSeconds: -1, maximumSeconds: 10)
        }
        #expect(throws: GameIdleElapsedPolicyError.nonPositiveMaximumSeconds(0)) {
            try GameIdleElapsedPolicy(maximumSeconds: 0)
        }
        #expect(
            throws: GameIdleElapsedPolicyError.minimumExceedsMaximum(
                minimum: 100,
                maximum: 10
            )
        ) {
            try GameIdleElapsedPolicy(minimumSeconds: 100, maximumSeconds: 10)
        }
    }

    @Test("경과 0 은 정산도 역행도 아니다")
    func zeroElapsed() {
        let outcome = GameIdleElapsedPolicy.standardV1.elapsed(from: base, to: base)
        #expect(outcome.settledSeconds == 0)
        #expect(outcome.rawSeconds == 0)
        #expect(outcome.isEmpty)
        #expect(!outcome.clockWentBackwards)
        #expect(!outcome.clockWasInvalid)
    }

    @Test("시계 역행은 0 으로 처리하고 표식을 남긴다")
    func backwardsClock() {
        let outcome = GameIdleElapsedPolicy.standardV1.elapsed(
            from: base,
            to: base.addingTimeInterval(-3600)
        )
        #expect(outcome.settledSeconds == 0)
        #expect(outcome.rawSeconds == 0)
        #expect(outcome.clockWentBackwards)
        #expect(!outcome.wasCapped)
    }

    @Test("초 미만은 내림한다")
    func flooring() {
        let outcome = GameIdleElapsedPolicy.standardV1.elapsed(
            from: base,
            to: base.addingTimeInterval(90.999)
        )
        #expect(outcome.rawSeconds == 90)
        #expect(outcome.settledSeconds == 90)
    }

    @Test("최소 임계 미만은 정산하지 않는다")
    func belowMinimum() {
        let policy = GameIdleElapsedPolicy.shortSessionV1
        let outcome = policy.elapsed(from: base, to: base.addingTimeInterval(59.9))
        #expect(outcome.rawSeconds == 59)
        #expect(outcome.settledSeconds == 0)
        #expect(outcome.wasBelowMinimum)
        #expect(outcome.unsettledSeconds == 59)
    }

    @Test("최소 임계와 정확히 같으면 정산한다")
    func exactlyMinimum() {
        let outcome = GameIdleElapsedPolicy.shortSessionV1.elapsed(
            from: base,
            to: base.addingTimeInterval(60)
        )
        #expect(outcome.settledSeconds == 60)
        #expect(!outcome.wasBelowMinimum)
    }

    @Test("캡을 넘으면 캡까지만 정산한다")
    func capped() {
        let outcome = GameIdleElapsedPolicy.shortSessionV1.elapsed(
            from: base,
            to: base.addingTimeInterval(9 * 3600)
        )
        #expect(outcome.rawSeconds == 32_400)
        #expect(outcome.settledSeconds == 28_800)
        #expect(outcome.wasCapped)
        #expect(outcome.unsettledSeconds == 3_600)
    }

    @Test("캡과 정확히 같으면 캡 표식이 붙지 않는다")
    func exactlyCap() {
        let outcome = GameIdleElapsedPolicy.shortSessionV1.elapsed(
            from: base,
            to: base.addingTimeInterval(8 * 3600)
        )
        #expect(outcome.settledSeconds == 28_800)
        #expect(!outcome.wasCapped)
    }

    @Test("NaN·무한대 구간은 계산 불가로 처리한다")
    func nonFiniteInterval() {
        for interval in [Double.nan, .infinity, -.infinity, .signalingNaN] {
            let outcome = GameIdleElapsedPolicy.standardV1.elapsed(interval: interval)
            #expect(outcome.clockWasInvalid)
            #expect(outcome.settledSeconds == 0)
            #expect(outcome.rawSeconds == 0)
        }
    }

    @Test("무한대 Date 가 섞여도 뺄셈 NaN 으로 새지 않는다")
    func nonFiniteDates() {
        let infinite = Date(timeIntervalSinceReferenceDate: .infinity)
        #expect(
            GameIdleElapsedPolicy.standardV1.elapsed(from: infinite, to: base).clockWasInvalid
        )
        #expect(
            GameIdleElapsedPolicy.standardV1.elapsed(from: base, to: infinite).clockWasInvalid
        )
        #expect(
            GameIdleElapsedPolicy.standardV1
                .elapsed(from: infinite, to: infinite)
                .clockWasInvalid
        )
    }

    @Test("Int 로 표현 못 할 만큼 큰 구간도 트랩 없이 포화된다")
    func integerSaturation() throws {
        let policy = try GameIdleElapsedPolicy(maximumSeconds: Int.max)
        let outcome = policy.elapsed(interval: 1e300)
        #expect(outcome.rawSeconds == GameIdleSeconds.maximumRepresentable)
        #expect(outcome.settledSeconds == GameIdleSeconds.maximumRepresentable)
        #expect(!outcome.wasCapped)
    }

    @Test("포화 변환은 음수·비유한을 0 으로 접는다")
    func saturatingHelper() {
        #expect(GameIdleSeconds.saturating(-1) == 0)
        #expect(GameIdleSeconds.saturating(.nan) == 0)
        #expect(GameIdleSeconds.saturating(.infinity) == 0)
        #expect(GameIdleSeconds.saturating(0) == 0)
        #expect(GameIdleSeconds.saturating(1.9) == 1)
        #expect(
            GameIdleSeconds.saturating(Double(GameIdleSeconds.maximumRepresentable) * 2)
                == GameIdleSeconds.maximumRepresentable
        )
    }

    @Test("덧셈은 오버플로 대신 포화한다")
    func addingSaturating() {
        #expect(GameIdleSeconds.addingSaturating(Int.max, 1) == Int.max)
        #expect(GameIdleSeconds.addingSaturating(Int.min, -1) == Int.min)
        #expect(GameIdleSeconds.addingSaturating(2, 3) == 5)
    }

    @Test("정책은 Codable 왕복에서 검증을 다시 거친다")
    func codable() throws {
        let policy = try GameIdleElapsedPolicy(
            minimumSeconds: 30,
            maximumSeconds: 300,
            overflow: .bank,
            belowMinimum: .discard
        )
        let data = try JSONEncoder().encode(policy)
        #expect(try JSONDecoder().decode(GameIdleElapsedPolicy.self, from: data) == policy)

        let broken = Data(
            #"{"minimumSeconds":-5,"maximumSeconds":10,"overflow":1,"belowMinimum":1}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GameIdleElapsedPolicy.self, from: broken)
        }
    }

    @Test("정산 초는 일/시/분/초로 쪼개진다")
    func durationBreakdown() {
        let duration = GameIdleDuration(totalSeconds: 90_061)
        #expect(duration.days == 1)
        #expect(duration.hours == 1)
        #expect(duration.minutes == 1)
        #expect(duration.seconds == 1)
        #expect(!duration.isZero)
        #expect(GameIdleDuration(totalSeconds: -5).totalSeconds == 0)
        #expect(GameIdleDuration(totalSeconds: 0).isZero)
    }
}
