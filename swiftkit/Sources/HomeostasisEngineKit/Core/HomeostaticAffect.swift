import Foundation

/// 항상성 상태 및 정동 벡터 단일 진실의 원천 (SSOT)
public struct HomeostaticAffect: Sendable, Equatable, Codable {
    public let valence: Double
    public let arousal: Double
    public let deltaH: Double
    public let isClosed: Bool

    public init(
        valence: Double,
        arousal: Double,
        deltaH: Double = 0.0,
        isClosed: Bool = false
    ) {
        self.valence = max(-1.0, min(1.0, valence))
        self.arousal = max(0.0, min(1.0, arousal))
        self.deltaH = deltaH
        self.isClosed = isClosed
    }

    /// 중립 상태
    public static let neutral = HomeostaticAffect(valence: 0.0, arousal: 0.0, deltaH: 0.0, isClosed: true)
}

/// Knuth/Welford 단일 패스 수치 안정 통계 연산기
/// 소표본 및 0 분산 시 0 나누기(NaN/Inf) 폭발을 수학적으로 원천 방어한다.
public struct WelfordAccumulator: Sendable, Equatable {
    public private(set) var count: Int = 0
    public private(set) var mean: Double = 0.0
    private var m2: Double = 0.0
    public let stabilizationEpsilon: Double

    public init(stabilizationEpsilon: Double = 0.01) {
        self.stabilizationEpsilon = max(1e-9, stabilizationEpsilon)
    }

    public mutating func update(_ value: Double) {
        guard value.isFinite else { return }
        count += 1
        let delta = value - mean
        mean += delta / Double(count)
        let delta2 = value - mean
        m2 += delta * delta2
    }

    /// 분산 산출 (소표본 모분산/표본분산 안전 처리)
    public var variance: Double {
        guard count > 1 else { return 0.0 }
        return max(0.0, m2 / Double(count))
    }

    /// 표준편차 (안정화 엡실론 가산으로 0 나누기 원천 차단)
    public var safeSigma: Double {
        return sqrt(variance) + stabilizationEpsilon
    }

    /// z-score 편차 (ΔH) 계산
    public func zScore(for value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return (value - mean) / safeSigma
    }
}

/// 비례-적분-미분 오차 피드백 제어기 (SuperInstance Biomimetic Control Loop)
public struct PIDController: Sendable, Equatable {
    public let kp: Double
    public let ki: Double
    public let kd: Double
    private var integral: Double = 0.0
    private var previousError: Double = 0.0

    public init(kp: Double, ki: Double, kd: Double) {
        self.kp = kp
        self.ki = ki
        self.kd = kd
    }

    public mutating func update(target: Double, current: Double, dt: Double) -> Double {
        guard dt > 0, target.isFinite, current.isFinite else { return 0.0 }
        let error = target - current
        integral += error * dt
        let derivative = (error - previousError) / dt
        previousError = error
        return (kp * error) + (ki * integral) + (kd * derivative)
    }

    public mutating func reset() {
        integral = 0.0
        previousError = 0.0
    }
}
