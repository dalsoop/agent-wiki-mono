import Foundation

/// Awake Trajectory Event
///
/// 기상/행동 단계에서 수집된 에이전트 전이(Transition) 궤적 단위.
/// 상태 특징 벡터(state), 행동(action), 보상(reward), 차기 상태(nextState), 지속 시간(duration), 종결 여부(isTerminal)를 보관한다.
public struct AwakeTrajectoryEvent: Sendable, Codable, Equatable {
    public let stepIndex: Int
    public let state: [Double]
    public let action: Int
    public let reward: Double
    public let nextState: [Double]
    public let duration: Double
    public let isTerminal: Bool

    public var step: Int { stepIndex }
    public var stateFeatures: [Double] { state }
    public var nextStateFeatures: [Double] { nextState }

    public init(
        stepIndex: Int,
        state: [Double],
        action: Int = 0,
        reward: Double = 0.0,
        nextState: [Double],
        duration: Double = 1.0,
        isTerminal: Bool = false
    ) {
        self.stepIndex = stepIndex
        self.state = state
        self.action = action
        self.reward = reward
        self.nextState = nextState
        self.duration = duration
        self.isTerminal = isTerminal
    }

    public init(
        step: Int,
        state: [Double],
        action: Int = 0,
        reward: Double = 0.0,
        nextState: [Double],
        duration: Double = 1.0,
        isTerminal: Bool = false
    ) {
        self.init(
            stepIndex: step,
            state: state,
            action: action,
            reward: reward,
            nextState: nextState,
            duration: duration,
            isTerminal: isTerminal
        )
    }
}

/// Consolidation Result
///
/// 각성 휴식 리플레이(Awake Rest Replay) 압축 및 LSTD 강화 공고화 연산 결과.
public struct ConsolidationResult: Sendable, Codable, Equatable {
    public let originalDuration: Double
    public let compressedDuration: Double
    public let compressionRatio: Double
    public let replayedEventsCount: Int
    public let featureDimension: Int
    public let weights: [Double]
    public let tdErrors: [Double]
    public let digest: UInt64
    public let digestHex: String

    public var replayedEventCount: Int { replayedEventsCount }

    public init(
        originalDuration: Double,
        compressedDuration: Double,
        compressionRatio: Double,
        replayedEventsCount: Int,
        featureDimension: Int,
        weights: [Double],
        tdErrors: [Double],
        digest: UInt64
    ) {
        self.originalDuration = originalDuration
        self.compressedDuration = compressedDuration
        self.compressionRatio = compressionRatio
        self.replayedEventsCount = replayedEventsCount
        self.featureDimension = featureDimension
        self.weights = weights
        self.tdErrors = tdErrors
        self.digest = digest
        self.digestHex = String(format: "%016llx", digest)
    }
}

/// Awake Rest Replay 에러 정의
public enum AwakeRestReplayError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyTrajectory
    case invalidCompressionRatio(Double)
    case dimensionMismatch(expected: Int, actual: Int)
    case featureDimensionMismatch(expected: Int, actual: Int, stepIndex: Int)
    case singularMatrix(column: Int)

    public var description: String {
        switch self {
        case .emptyTrajectory:
            return "Trajectory cannot be empty for awake rest replay consolidation."
        case .invalidCompressionRatio(let ratio):
            return "Invalid compression ratio: \(ratio). Must be greater than 0."
        case .dimensionMismatch(let expected, let actual):
            return "Matrix dimension mismatch: expected \(expected), actual \(actual)."
        case .featureDimensionMismatch(let expected, let actual, let stepIndex):
            return "Feature dimension mismatch at step \(stepIndex): expected \(expected), actual \(actual)."
        case .singularMatrix(let column):
            return "Singular matrix encountered during Gauss-Jordan elimination at column \(column)."
        }
    }
}

/// Awake Rest Replay Engine
///
/// 해마성 각성 휴식 리플레이(Awake Rest Replay) 메커니즘을 모사하는 결정론적 오프라인 통합 엔진.
///
/// [주요 설계 사양]:
/// 1. 20배속 시간 압축 (20x Time Compression): 기상 시 행동 궤적의 지속 시간을 기본 20배 압축하여 리플레이.
/// 2. 역방향 LSTD 통계량 누적 (Backward LSTD Statistic Accumulation): 사건 궤적을 역순으로 리플레이하며 A matrix 및 b vector 누적.
/// 3. 가우스-요르단 부분 피보팅 풀이 (Gauss-Jordan Partial Pivoting): A w = b 선형 시스템을 수치적으로 안정되게 직접 해법으로 산출.
/// 4. FNV-1a 64비트 다이제스트: 공고화 산출물(가중치, 오차, 압축 지표)을 결정론적 비트 해시로 검증.
public struct AwakeRestReplayEngine: Sendable {
    public static let defaultCompressionRatio: Double = 20.0
    public static let defaultDiscountFactor: Double = 0.99
    public static let defaultRegularization: Double = 1e-4

    public let compressionRatio: Double
    public let discountFactor: Double
    public let regularization: Double

    public init(
        compressionRatio: Double = defaultCompressionRatio,
        discountFactor: Double = defaultDiscountFactor,
        regularization: Double = defaultRegularization
    ) {
        self.compressionRatio = compressionRatio
        self.discountFactor = discountFactor
        self.regularization = regularization
    }

    /// 궤적 공고화 실행
    public func consolidate(trajectory: [AwakeTrajectoryEvent]) throws -> ConsolidationResult {
        guard compressionRatio > 0 else {
            throw AwakeRestReplayError.invalidCompressionRatio(compressionRatio)
        }

        guard !trajectory.isEmpty else {
            throw AwakeRestReplayError.emptyTrajectory
        }

        let dimension = trajectory[0].state.count
        guard dimension > 0 else {
            throw AwakeRestReplayError.featureDimensionMismatch(expected: 1, actual: 0, stepIndex: trajectory[0].stepIndex)
        }

        // 궤적 유효성 및 차원 일관성 검증
        var originalDuration: Double = 0.0
        for event in trajectory {
            guard event.state.count == dimension else {
                throw AwakeRestReplayError.featureDimensionMismatch(expected: dimension, actual: event.state.count, stepIndex: event.stepIndex)
            }
            guard event.nextState.count == dimension else {
                throw AwakeRestReplayError.featureDimensionMismatch(expected: dimension, actual: event.nextState.count, stepIndex: event.stepIndex)
            }
            originalDuration += max(0.0, event.duration)
        }

        // 1. 20배속 시간 압축
        let compressedDuration = originalDuration / compressionRatio

        // 2. 역방향 LSTD 통계량 누적 (Backward Accumulation)
        // A = sum(phi_t * (phi_t - gamma * phi_{t+1})^T) + regularization * I
        // b = sum(phi_t * reward_t)
        var A = [[Double]](repeating: [Double](repeating: 0.0, count: dimension), count: dimension)
        for i in 0..<dimension {
            A[i][i] = regularization
        }
        var b = [Double](repeating: 0.0, count: dimension)

        let reversedTrajectory = trajectory.reversed()
        for event in reversedTrajectory {
            let phi = event.state
            let phiNext = event.isTerminal ? [Double](repeating: 0.0, count: dimension) : event.nextState
            let reward = event.reward

            for i in 0..<dimension {
                let phi_i = phi[i]
                for j in 0..<dimension {
                    A[i][j] += phi_i * (phi[j] - discountFactor * phiNext[j])
                }
                b[i] += phi_i * reward
            }
        }

        // 3. 가우스-요르단 부분 피보팅 풀이 (Gauss-Jordan with Partial Pivoting)
        let weights = try Self.solveGaussJordan(matrix: A, vector: b)

        // 4. 시간차 오차 (TD Errors) 순방향 계산
        var tdErrors = [Double]()
        tdErrors.reserveCapacity(trajectory.count)
        for event in trajectory {
            var vState = 0.0
            var vNext = 0.0
            for j in 0..<dimension {
                vState += event.state[j] * weights[j]
                if !event.isTerminal {
                    vNext += event.nextState[j] * weights[j]
                }
            }
            let tdError = event.reward + discountFactor * vNext - vState
            tdErrors.append(tdError)
        }

        // 5. FNV-1a 64비트 다이제스트 생성
        let digest = Self.computeDigest(
            eventCount: trajectory.count,
            featureDimension: dimension,
            originalDuration: originalDuration,
            compressedDuration: compressedDuration,
            weights: weights,
            tdErrors: tdErrors
        )

        return ConsolidationResult(
            originalDuration: originalDuration,
            compressedDuration: compressedDuration,
            compressionRatio: compressionRatio,
            replayedEventsCount: trajectory.count,
            featureDimension: dimension,
            weights: weights,
            tdErrors: tdErrors,
            digest: digest
        )
    }

    /// 가우스-요르단 소거법 (부분 피보팅 적용)
    public static func solveGaussJordan(matrix A: [[Double]], vector b: [Double]) throws -> [Double] {
        let n = b.count
        guard A.count == n else {
            throw AwakeRestReplayError.dimensionMismatch(expected: n, actual: A.count)
        }
        for row in A {
            guard row.count == n else {
                throw AwakeRestReplayError.dimensionMismatch(expected: n, actual: row.count)
            }
        }

        if n == 0 {
            return []
        }

        // 첨가 행렬 [A | b] 구성
        var M = [[Double]](repeating: [Double](repeating: 0.0, count: n + 1), count: n)
        for i in 0..<n {
            for j in 0..<n {
                M[i][j] = A[i][j]
            }
            M[i][n] = b[i]
        }

        for k in 0..<n {
            // 부분 피보팅: k열에서 절대값이 가장 큰 행을 선택
            var maxVal = abs(M[k][k])
            var pivotRow = k
            for row in (k + 1)..<n {
                let val = abs(M[row][k])
                if val > maxVal {
                    maxVal = val
                    pivotRow = row
                }
            }

            if maxVal < 1e-15 {
                throw AwakeRestReplayError.singularMatrix(column: k)
            }

            if pivotRow != k {
                M.swapAt(k, pivotRow)
            }

            // 피벗 행 정규화 (M[k][k] -> 1.0)
            let pivot = M[k][k]
            for j in k...n {
                M[k][j] /= pivot
            }

            // 타 행 소거 (M[row][k] -> 0.0)
            for row in 0..<n {
                if row == k { continue }
                let factor = M[row][k]
                if abs(factor) > 1e-18 {
                    for j in k...n {
                        M[row][j] -= factor * M[k][j]
                    }
                }
            }
        }

        var x = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            x[i] = M[i][n]
        }
        return x
    }

    /// FNV-1a 64비트 해시 함수
    public static func fnv1a64(bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    /// 공고화 결과에 대한 결정론적 FNV-1a 64비트 다이제스트 산출
    public static func computeDigest(
        eventCount: Int,
        featureDimension: Int,
        originalDuration: Double,
        compressedDuration: Double,
        weights: [Double],
        tdErrors: [Double]
    ) -> UInt64 {
        var buffer = [UInt8]()
        buffer.reserveCapacity(32 + (weights.count + tdErrors.count) * 8)

        func appendUInt64(_ value: UInt64) {
            var be = value.bigEndian
            withUnsafeBytes(of: &be) { rawBytes in
                buffer.append(contentsOf: rawBytes)
            }
        }

        appendUInt64(UInt64(eventCount))
        appendUInt64(UInt64(featureDimension))
        appendUInt64(originalDuration.bitPattern)
        appendUInt64(compressedDuration.bitPattern)

        for w in weights {
            appendUInt64(w.bitPattern)
        }
        for err in tdErrors {
            appendUInt64(err.bitPattern)
        }

        return fnv1a64(bytes: buffer)
    }

    /// 편의 정적 실행 메서드
    public static func consolidate(
        trajectory: [AwakeTrajectoryEvent],
        compressionRatio: Double = defaultCompressionRatio,
        discountFactor: Double = defaultDiscountFactor,
        regularization: Double = defaultRegularization
    ) throws -> ConsolidationResult {
        let engine = AwakeRestReplayEngine(
            compressionRatio: compressionRatio,
            discountFactor: discountFactor,
            regularization: regularization
        )
        return try engine.consolidate(trajectory: trajectory)
    }
}
