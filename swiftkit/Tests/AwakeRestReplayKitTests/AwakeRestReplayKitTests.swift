import XCTest
@testable import AwakeRestReplayKit

final class AwakeRestReplayKitTests: XCTestCase {

    /// 동일 궤적 1,000회 연속 실행 시 비트 다이제스트 100% 일치 단위 테스트 검증
    func testBitDigestIdenticalAcross1000ConsecutiveRuns() throws {
        // 결정론적 비난수 궤적 생성 (Token=0, 난수 배제)
        var trajectory = [AwakeTrajectoryEvent]()
        let stepCount = 20
        let dimension = 4

        for step in 0..<stepCount {
            let s0 = Double(step) * 0.1
            let s1 = Double(step * step) * 0.01
            let s2 = cos(Double(step))
            let s3 = sin(Double(step))
            let state = [s0, s1, s2, s3]

            let nextStep = step + 1
            let ns0 = Double(nextStep) * 0.1
            let ns1 = Double(nextStep * nextStep) * 0.01
            let ns2 = cos(Double(nextStep))
            let ns3 = sin(Double(nextStep))
            let nextState = [ns0, ns1, ns2, ns3]

            let isTerminal = (step == stepCount - 1)
            let reward = isTerminal ? 10.0 : (Double(step % 3) - 1.0)
            let duration = 0.5 + Double(step % 4) * 0.25

            let event = AwakeTrajectoryEvent(
                stepIndex: step,
                state: state,
                action: step % 2,
                reward: reward,
                nextState: nextState,
                duration: duration,
                isTerminal: isTerminal
            )
            trajectory.append(event)
        }

        let engine = AwakeRestReplayEngine(
            compressionRatio: 20.0,
            discountFactor: 0.95,
            regularization: 1e-4
        )

        // 기준 1회차 실행
        let baselineResult = try engine.consolidate(trajectory: trajectory)
        let baselineDigest = baselineResult.digest
        let baselineHex = baselineResult.digestHex

        XCTAssertNotEqual(baselineDigest, 0)
        XCTAssertEqual(baselineHex.count, 16)
        XCTAssertEqual(baselineResult.replayedEventsCount, stepCount)
        XCTAssertEqual(baselineResult.featureDimension, dimension)

        // 1,000회 연속 실행 및 비트 다이제스트 100% 일치 검증
        for iteration in 1...1000 {
            let result = try engine.consolidate(trajectory: trajectory)
            XCTAssertEqual(
                result.digest,
                baselineDigest,
                "Digest mismatch at iteration \(iteration)"
            )
            XCTAssertEqual(
                result.digestHex,
                baselineHex,
                "Digest hex mismatch at iteration \(iteration)"
            )
            XCTAssertEqual(
                result.weights,
                baselineResult.weights,
                "Weights mismatch at iteration \(iteration)"
            )
            XCTAssertEqual(
                result.tdErrors,
                baselineResult.tdErrors,
                "TD errors mismatch at iteration \(iteration)"
            )
        }
    }

    /// 20배속 시간 압축(20x Compression) 검증
    func testTimeCompression20x() throws {
        let events = [
            AwakeTrajectoryEvent(stepIndex: 0, state: [1.0, 0.0], reward: 0.0, nextState: [0.0, 1.0], duration: 10.0),
            AwakeTrajectoryEvent(stepIndex: 1, state: [0.0, 1.0], reward: 1.0, nextState: [0.0, 0.0], duration: 30.0, isTerminal: true)
        ]

        let engine = AwakeRestReplayEngine(compressionRatio: 20.0)
        let result = try engine.consolidate(trajectory: events)

        XCTAssertEqual(result.originalDuration, 40.0, accuracy: 1e-9)
        XCTAssertEqual(result.compressedDuration, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.compressionRatio, 20.0, accuracy: 1e-9)
    }

    /// 가우스-요르단 부분 피보팅 풀이 수치 정확도 검증
    func testGaussJordanPartialPivotingSolver() throws {
        // 피보팅이 필수적인 선형 시스템
        // [0  2  1] [x0]   [4]
        // [1 -1  1] [x1] = [-1]
        // [2  1  1] [x2] = [1]
        // 해: x0 = -0.8, x1 = 1.4, x2 = 1.2
        let A: [[Double]] = [
            [0.0, 2.0, 1.0],
            [1.0, -1.0, 1.0],
            [2.0, 1.0, 1.0]
        ]
        let b: [Double] = [4.0, -1.0, 1.0]

        let x = try AwakeRestReplayEngine.solveGaussJordan(matrix: A, vector: b)

        XCTAssertEqual(x.count, 3)
        XCTAssertEqual(x[0], -0.8, accuracy: 1e-9)
        XCTAssertEqual(x[1], 1.4, accuracy: 1e-9)
        XCTAssertEqual(x[2], 1.2, accuracy: 1e-9)
    }

    /// 특이 행렬(Singular Matrix) 예외 처리 검증
    func testSingularMatrixError() {
        let singularA: [[Double]] = [
            [1.0, 2.0],
            [2.0, 4.0]
        ]
        let b: [Double] = [3.0, 6.0]

        XCTAssertThrowsError(try AwakeRestReplayEngine.solveGaussJordan(matrix: singularA, vector: b)) { error in
            guard let replayError = error as? AwakeRestReplayError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            if case .singularMatrix = replayError {
                // Expected
            } else {
                XCTFail("Expected singularMatrix error, got: \(replayError)")
            }
        }
    }

    /// FNV-1a 64비트 표준 테스트 벡터 및 결정론 검증
    func testFNV1a64DigestVectors() {
        let emptyHash = AwakeRestReplayEngine.fnv1a64(bytes: [])
        XCTAssertEqual(emptyHash, 0xcbf29ce484222325)

        let testBytes = Array("test".utf8)
        let testHash = AwakeRestReplayEngine.fnv1a64(bytes: testBytes)
        XCTAssertNotEqual(testHash, 0xcbf29ce484222325)

        // 동일 바이트 반복 해싱 일관성
        let testHashRepeat = AwakeRestReplayEngine.fnv1a64(bytes: testBytes)
        XCTAssertEqual(testHash, testHashRepeat)
    }

    /// 빈 궤적 및 차원 불일치 에러 검증
    func testValidationErrors() {
        let engine = AwakeRestReplayEngine()

        // 1. 빈 궤적
        XCTAssertThrowsError(try engine.consolidate(trajectory: [])) { error in
            XCTAssertEqual(error as? AwakeRestReplayError, .emptyTrajectory)
        }

        // 2. 상태 차원 불일치
        let mismatchedTrajectory = [
            AwakeTrajectoryEvent(stepIndex: 0, state: [1.0, 2.0], reward: 0.0, nextState: [1.0, 2.0], duration: 1.0),
            AwakeTrajectoryEvent(stepIndex: 1, state: [1.0, 2.0, 3.0], reward: 0.0, nextState: [1.0, 2.0], duration: 1.0)
        ]
        XCTAssertThrowsError(try engine.consolidate(trajectory: mismatchedTrajectory)) { error in
            if case .featureDimensionMismatch(let expected, let actual, let step) = (error as? AwakeRestReplayError) {
                XCTAssertEqual(expected, 2)
                XCTAssertEqual(actual, 3)
                XCTAssertEqual(step, 1)
            } else {
                XCTFail("Expected featureDimensionMismatch, got \(error)")
            }
        }
    }
}
