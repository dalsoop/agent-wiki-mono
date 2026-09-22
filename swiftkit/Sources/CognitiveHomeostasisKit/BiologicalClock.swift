import Foundation

// MARK: - 1. 자율신경 톤 벡터 (Autonomic Tone Vector)
/// 테이어 & 레인(Julian F. Thayer & Richard D. Lane, 2000, 2009)의 중추자율신경망(CAN) 원심성 명령.
public struct CognitiveAutonomicToneVector: Sendable, Equatable, Codable {
    /// 교감신경 드라이브 [0.0, 1.0]: 심박 가속, 투쟁-도피 동원
    public let sympathetic: Double
    /// 부교감 미주신경 톤 [0.0, 1.0]: 미주신경 브레이크(Vagal Brake), 심박 감속 및 안정화
    public let vagal: Double

    public init(sympathetic: Double, vagal: Double) {
        self.sympathetic = max(0.0, min(1.0, sympathetic))
        self.vagal = max(0.0, min(1.0, vagal))
    }

    /// 정상 안녕(Safe) 상태 기본 톤: 강한 미주신경 브레이크, 낮은 교감
    public static let safeHomeostatic = CognitiveAutonomicToneVector(sympathetic: 0.15, vagal: 0.85)

    /// 비상 스트레스/고통 상태 톤: 미주신경 브레이크 급속 해제, 높은 교감
    public static let distressEmergency = CognitiveAutonomicToneVector(sympathetic: 0.90, vagal: 0.05)
}

// MARK: - 2. 동방결절 막전위 위상 진동자 (Pacemaker Phase Oscillator)
/// 반데르폴(Van der Pol) 및 쿠라모토(Kuramoto) 생체 비선형 진동자 모델.
/// 외부 타이머 sleep 없이 자체 막전위 위상 누적(dφ/dt)으로 박동을 자율 생성한다.
public struct CognitivePacemakerOscillator: Sendable, Equatable {
    /// 현재 위상 [0, 2π)
    public private(set) var phase: Double
    /// 내인성 고유 주파수 (Hz, e.g. 1.5 Hz = 90 BPM)
    public var intrinsicFrequency: Double
    /// 세포 간 결합 강도 K
    public var couplingStrength: Double

    public init(
        phase: Double = 0.0,
        intrinsicFrequency: Double = 1.0,
        couplingStrength: Double = 0.15
    ) {
        self.phase = phase
        self.intrinsicFrequency = intrinsicFrequency
        self.couplingStrength = couplingStrength
    }

    /// 물리 시간 dt(초)와 자율신경 드라이브에 따라 위상을 1스텝 적분한다.
    /// 위상이 2π를 초과하면 true를 반환하며 1회 박동(Firing)을 방출한다.
    public mutating func step(dt: Double, autonomicDrive: Double, externalPhase: Double? = nil) -> Bool {
        var dphi = (intrinsicFrequency + autonomicDrive) * 2.0 * .pi
        if let theta = externalPhase {
            dphi += couplingStrength * sin(theta - phase)
        }
        phase += dphi * dt
        if phase >= 2.0 * .pi {
            phase -= 2.0 * .pi
            return true
        }
        return false
    }
}

// MARK: - 3. 알로스타틱 대사 에너지 예산 수지 (Metabolic Energy Ledger)
/// 피터 스털링(Peter Sterling, 2012)과 리사 펠드먼 바렛(Lisa Feldman Barrett, 2017)의 신체 예산 배분.
/// dE/dt = -P_base(BMR) - P_act + I_meta
public struct CognitiveMetabolicEnergyLedger: Sendable, Equatable {
    public static let maxCapacity: Double = 1000.0
    public private(set) var energy: Double
    public private(set) var allostaticLoad: Double
    /// 기저대사율 (BMR: 초당 기저 소모량)
    public let baseMetabolicRate: Double

    public init(
        initialEnergy: Double = 1000.0,
        baseMetabolicRate: Double = 1.0
    ) {
        self.energy = initialEnergy
        self.allostaticLoad = 0.0
        self.baseMetabolicRate = baseMetabolicRate
    }

    /// 물리 시간 경과에 따른 기저대사(BMR) 소모
    public mutating func consumeBasal(dt: Double) {
        let cost = baseMetabolicRate * dt
        energy = max(0.0, energy - cost)
        if energy < 200.0 {
            allostaticLoad += (200.0 - energy) * dt * 0.01
        }
    }

    /// 1회 심박 박출에 필요한 활동 대사 에너지 소모
    public mutating func consumeForBeat(strokeCost: Double = 1.0) -> Bool {
        guard energy >= strokeCost else {
            allostaticLoad += strokeCost * 0.5
            return false // 탈진 (Exhaustion)
        }
        energy -= strokeCost
        return true
    }

    /// 대사 에너지 재충전
    public mutating func recharge(intake: Double) {
        energy = min(Self.maxCapacity, energy + intake)
    }

    /// 즉시 모든 대사 에너지를 고갈시킨다 (테스트 및 한계 시뮬레이션용)
    public mutating func drainAllEnergyForTesting() {
        energy = 0.0
    }
}

// MARK: - 4. 박간 간격 실측 (InterBeatInterval)
public struct CognitiveInterBeatInterval: Sendable, Equatable {
    public let seconds: Double

    public init(seconds: Double) {
        precondition(seconds > 0, "inter-beat interval must be a measured positive duration")
        self.seconds = seconds
    }
}
