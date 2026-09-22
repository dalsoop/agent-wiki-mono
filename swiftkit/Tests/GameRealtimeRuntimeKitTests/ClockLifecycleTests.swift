import GameRealtimeProtocolKit
import GameRealtimeRuntimeKit
import GameRealtimeStateKit
import XCTest

final class ClockLifecycleTests: XCTestCase {
    func testPauseClearsAccumulatorAndResumeDoesNotCatchUp() throws {
        let input = try makeInput(sequence: 1)
        var accumulator = FixedTickAccumulator()
        accumulator.setHeldInput(input)
        try accumulator.enqueuePendingRawInput(input)

        var ticks = 0
        let partial = accumulator.consume(elapsed: .milliseconds(20)) { _ in
            ticks += 1
        }
        XCTAssertEqual(partial.executedTicks, 0)
        XCTAssertEqual(accumulator.accumulatedElapsed, .milliseconds(20))

        accumulator.transition(to: .paused)
        XCTAssertEqual(accumulator.lifecycle, .paused)
        XCTAssertEqual(accumulator.accumulatedElapsed, .zero)
        XCTAssertNil(accumulator.heldInput)
        XCTAssertTrue(accumulator.pendingRawInputs.isEmpty)

        let dormant = accumulator.consume(elapsed: .seconds(30)) { _ in
            ticks += 1
        }
        XCTAssertEqual(dormant.executedTicks, 0)
        XCTAssertEqual(ticks, 0)
        XCTAssertEqual(accumulator.accumulatedElapsed, .zero)

        accumulator.transition(to: .active)
        let resumed = accumulator.consume(
            elapsed: TickPolicy.standardV1.fixedStep
        ) { step in
            XCTAssertEqual(step, TickPolicy.standardV1.fixedStep)
            ticks += 1
        }
        XCTAssertEqual(resumed.executedTicks, 1)
        XCTAssertEqual(resumed.discardedTicks, 0)
        XCTAssertEqual(ticks, 1)
        XCTAssertEqual(accumulator.accumulatedElapsed, .zero)
    }

    func testStandardPolicyClampsRunsFiveAndDiscardsBacklog() throws {
        let policy = TickPolicy.standardV1
        XCTAssertEqual(policy.fixedStep, .seconds(1) / 30)
        XCTAssertEqual(policy.maxCatchUpTicks, 5)
        XCTAssertEqual(policy.maxElapsedClamp, .milliseconds(250))
        XCTAssertEqual(policy.backlogPolicy, .discardAfterCatchUpLimit)

        var accumulator = FixedTickAccumulator(policy: policy)
        var ticks = 0
        let report = accumulator.consume(elapsed: .seconds(10)) { _ in
            ticks += 1
        }

        XCTAssertEqual(report.suppliedElapsed, .seconds(10))
        XCTAssertEqual(report.consumedElapsed, .milliseconds(250))
        XCTAssertEqual(report.executedTicks, 5)
        XCTAssertEqual(report.discardedTicks, 2)
        XCTAssertEqual(report.remainingElapsed, .zero)
        XCTAssertEqual(ticks, 5)
        XCTAssertEqual(accumulator.accumulatedElapsed, .zero)
    }

    func testBackgroundClearsTimingAndInputsAndDoesNotMutateTicks() throws {
        let input = try makeInput(sequence: 2)
        var accumulator = FixedTickAccumulator()
        accumulator.setHeldInput(input)
        try accumulator.enqueuePendingRawInput(input)
        _ = accumulator.consume(elapsed: .milliseconds(10)) { _ in }

        accumulator.transition(to: .background)
        var ticks = 41
        let report = accumulator.consume(elapsed: .seconds(2)) { _ in
            ticks += 1
        }

        XCTAssertEqual(report.executedTicks, 0)
        XCTAssertEqual(ticks, 41)
        XCTAssertEqual(accumulator.accumulatedElapsed, .zero)
        XCTAssertNil(accumulator.heldInput)
        XCTAssertTrue(accumulator.pendingRawInputs.isEmpty)
    }

    func testManualClockOnlyAdvancesWhenDirected() throws {
        let start = ContinuousClock().now
        var clock = ManualGameRealtimeClock(startingAt: start)

        XCTAssertEqual(clock.now(), start)
        try clock.advance(by: .milliseconds(125))
        XCTAssertEqual(start.duration(to: clock.now()), .milliseconds(125))
        XCTAssertEqual(clock.now(), clock.now())
    }

    func testInvalidTickPoliciesRejectZeroAndNegativeBoundaries() {
        for invalidStep in [Duration.zero, .nanoseconds(-1)] {
            XCTAssertThrowsError(
                try TickPolicy(
                    fixedStep: invalidStep,
                    maxCatchUpTicks: 1,
                    maxElapsedClamp: .milliseconds(1),
                    backlogPolicy: .discardAfterCatchUpLimit
                )
            ) { error in
                XCTAssertEqual(
                    error as? TickPolicyError,
                    .nonPositiveFixedStep(invalidStep)
                )
            }
        }
        for invalidCatchUp in [0, -1] {
            XCTAssertThrowsError(
                try TickPolicy(
                    fixedStep: .milliseconds(1),
                    maxCatchUpTicks: invalidCatchUp,
                    maxElapsedClamp: .milliseconds(1),
                    backlogPolicy: .discardAfterCatchUpLimit
                )
            ) { error in
                XCTAssertEqual(
                    error as? TickPolicyError,
                    .nonPositiveMaxCatchUpTicks(invalidCatchUp)
                )
            }
        }
        for invalidClamp in [Duration.zero, .nanoseconds(-1)] {
            XCTAssertThrowsError(
                try TickPolicy(
                    fixedStep: .milliseconds(1),
                    maxCatchUpTicks: 1,
                    maxElapsedClamp: invalidClamp,
                    backlogPolicy: .discardAfterCatchUpLimit
                )
            ) { error in
                XCTAssertEqual(
                    error as? TickPolicyError,
                    .nonPositiveMaxElapsedClamp(invalidClamp)
                )
            }
        }
    }

    func testManualClockRejectsNegativeAdvance() {
        let start = ContinuousClock().now
        var clock = ManualGameRealtimeClock(startingAt: start)

        XCTAssertThrowsError(
            try clock.advance(by: .nanoseconds(-1))
        ) { error in
            XCTAssertEqual(
                error as? ManualGameRealtimeClockError,
                .negativeAdvance(.nanoseconds(-1))
            )
        }
        XCTAssertEqual(clock.now(), start)
    }

    private func makeInput(sequence: UInt64) throws -> CombatInputFrame {
        try CombatInputFrame(
            targetTick: 1,
            controlledEntity: EntityHandle(index: 0, generation: 1),
            sequence: sequence,
            source: .manual,
            move: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            aim: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            buttons: []
        )
    }
}
