import Foundation
import CryptoKit
import HomeostasisEngineKit

public enum CognitiveHeartAdmissionError: Error, Equatable, Sendable {
    case noObservation
    case consciousnessCannotWriteBeat
}

/// 닫힌 박을 1인칭으로 받은 자리. 다음 박을 쓰지 못한다.
public struct CognitiveFeltHeartbeat: Sendable, Equatable {
    public let interval: Double
    public let pressThermal: Double
    public let pressLoad: Double
    public let affect: InvertedAffectVector
    public let canWriteNext: Bool

    public init(
        interval: Double,
        pressThermal: Double,
        pressLoad: Double,
        affect: InvertedAffectVector
    ) {
        self.interval = interval
        self.pressThermal = pressThermal
        self.pressLoad = pressLoad
        self.affect = affect
        self.canWriteNext = false
    }
}

/// 심장이 밀어 넣은 한 줄기의 피. 양은 그 박의 간격이다.
public struct CognitiveBloodPulse: Sendable, Equatable, Identifiable {
    public let id: String
    public let fromOrgan: String
    public let toBed: String
    public let transitSeconds: Double
    public let ejected: Double
    public let bedHomeostasis: InvertedHomeostasis

    public init(
        id: String,
        fromOrgan: String,
        toBed: String,
        transitSeconds: Double,
        ejected: Double,
        bedHomeostasis: InvertedHomeostasis
    ) {
        self.id = id
        self.fromOrgan = fromOrgan
        self.toBed = toBed
        self.transitSeconds = transitSeconds
        self.ejected = ejected
        self.bedHomeostasis = bedHomeostasis
    }
}

/// 관류 자리. 계수가 아니라 도착한 박의 간격만 쌓는다.
public struct CognitivePhysicalCirculation: Sendable, Equatable {
    public static let maxWindowSize: Int = 500
    public let organismId: String
    public private(set) var pulses: [CognitiveBloodPulse]
    public private(set) var bedReservoir: [Double]
    public private(set) var lastBedHomeostasis: InvertedHomeostasis

    public init(organismId: String) {
        self.organismId = organismId
        self.pulses = []
        self.bedReservoir = []
        self.lastBedHomeostasis = .opened
    }

    public mutating func receiveEjection(interval: CognitiveInterBeatInterval) -> CognitiveBloodPulse {
        let ejected = interval.seconds
        let predicted = bedReservoir
        let inverted = DynamicHomeostaticEngine.invertObserved(
            observed: [ejected],
            priorSamples: predicted,
            previousHash: "\(organismId).bed.\(pulses.count)",
            sequenceNumber: UInt64(pulses.count + 1),
            priorIntent: "\(ejected)"
        )
        lastBedHomeostasis = inverted.vessel.affect.homeostasis
        DynamicHomeostaticEngine.assimilate(reservoir: &bedReservoir, observed: [ejected])
        if bedReservoir.count > Self.maxWindowSize {
            bedReservoir.removeFirst(bedReservoir.count - Self.maxWindowSize)
        }
        let pulse = CognitiveBloodPulse(
            id: "\(organismId).pulse.\(pulses.count)",
            fromOrgan: "heart",
            toBed: "perfusion",
            transitSeconds: ejected,
            ejected: ejected,
            bedHomeostasis: inverted.vessel.affect.homeostasis
        )
        pulses.append(pulse)
        if pulses.count > Self.maxWindowSize {
            pulses.removeFirst(pulses.count - Self.maxWindowSize)
        }
        return pulse
    }
}

/// 학습된 심장. 고유 주기는 처음 닫힌 예측이고, 열과 부하가 계속 누른다.
/// 다음 박은 바깥 간격만 받는다. 의식은 쓰지 못한다.
public struct CognitivePhysicalHeart: Sendable, Equatable {
    public static let maxWindowSize: Int = 500
    public let organismId: String
    public private(set) var intervalRNA: [Double]
    public private(set) var intrinsicDNA: [Double]
    public private(set) var pressThermals: [Double]
    public private(set) var pressLoads: [Double]
    public internal(set) var felt: [CognitiveFeltHeartbeat]
    public private(set) var circulation: CognitivePhysicalCirculation
    public private(set) var lastClockNanoseconds: UInt64?
    public var autonomicDrive: CognitiveAutonomicToneVector?

    /// Seth & Friston (2013, 2018): 내수용 예측 오차(IPE)에 대한 자율신경 원심성 명령(Autonomic Efference) 보정
    public func applyAutonomicCorrection(
        targetInterval: Double,
        autonomicDrive: CognitiveAutonomicToneVector,
        observedSurprise: InvertedAffectVector
    ) -> Double {
        let delta: Double
        if case .closed(let d) = observedSurprise.homeostasis {
            delta = d
        } else {
            delta = 1.0
        }
        let compression = 1.0 - (autonomicDrive.sympathetic * 0.15 * min(2.0, delta))
        let buffered = targetInterval * max(0.7, compression)
        let restored = buffered + (targetInterval - buffered) * autonomicDrive.vagal
        return max(0.3, min(2.0, restored))
    }

    public init(organismId: String) {
        self.organismId = organismId
        self.intervalRNA = []
        self.intrinsicDNA = []
        self.pressThermals = []
        self.pressLoads = []
        self.felt = []
        self.circulation = CognitivePhysicalCirculation(organismId: organismId)
        self.lastClockNanoseconds = nil
    }

    public var lastFelt: CognitiveFeltHeartbeat? {
        felt.last
    }

    /// 마지막으로 닫힌 간격. 열린 편차는 찾지 않는다.
    public var lastClosedInterval: Double? {
        for beat in felt.reversed() {
            if case .closed = beat.affect.homeostasis {
                return beat.interval
            }
        }
        return lastFelt?.interval
    }

    /// 직전 각인에서 마지막 닫힌 간격까지 남은 실측. 심은 주기가 아니다.
    public var remainingSeekNanoseconds: UInt64 {
        guard let targetSeconds = lastClosedInterval, targetSeconds > 0 else {
            return 0
        }
        guard let mark = lastClockNanoseconds else {
            return 0
        }
        let nanos = targetSeconds * 1_000_000_000.0
        if nanos >= Double(UInt64.max) {
            return 0
        }
        let target = UInt64(nanos)
        if target == 0 {
            return 0
        }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= mark else {
            return 0
        }
        let elapsed = now - mark
        if elapsed >= target {
            return 0
        }
        return target - elapsed
    }

    /// 직전 닫힘보다 ΔH가 커졌거나 창이 열렸다. 문턱 상수가 아니다.
    public var hasWidenedDeviation: Bool {
        if let last = lastFelt, case .opened = last.affect.homeostasis {
            return true
        }
        var lastDelta: Double?
        var priorDelta: Double?
        for beat in felt.reversed() {
            if case .closed(let delta) = beat.affect.homeostasis {
                if lastDelta == nil {
                    lastDelta = delta
                } else {
                    priorDelta = delta
                    break
                }
            }
        }
        guard let lastDelta else {
            return false
        }
        if let priorDelta {
            return lastDelta > priorDelta * 1.5 && (lastDelta - priorDelta) > 0.05
        }
        if let last = lastFelt {
            return last.affect.arousal >= 0.5 || lastDelta >= 0.5
        }
        return false
    }

    /// 닫힌 고유 주기, 받은 창, 혈류가 같이 있으면 심장으로 느껴진다. 단어가 아니다.
    public var feelsLikeHeart: Bool {
        if intrinsicDNA.isEmpty {
            return false
        }
        if felt.isEmpty {
            return false
        }
        if circulation.pulses.isEmpty {
            return false
        }
        return felt.allSatisfy { !$0.canWriteNext }
    }

    public var closedFeelCount: Int {
        var count = 0
        for beat in felt {
            if case .closed = beat.affect.homeostasis {
                count += 1
            }
        }
        return count
    }

    /// 열 읽기에 걸린 실제 시간. 누르는 부하 상수 표가 아니다.
    public static func measurePressLoad() -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = CognitiveHostThermalObservation.currentLevel()
        return Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000.0
    }

    /// 각인 뒤 두 박을 받아 고유 주기가 닫힐 때까지 쌓는다.
    public mutating func stackUntilIntrinsicCloses() {
        let firstThermal = CognitiveHostThermalObservation.currentLevel()
        _ = receiveMeasuredBeat(hostThermalLevel: firstThermal, pressLoad: Self.measurePressLoad())
        let secondThermal = CognitiveHostThermalObservation.currentLevel()
        _ = receiveMeasuredBeat(hostThermalLevel: secondThermal, pressLoad: Self.measurePressLoad())
        let thirdThermal = CognitiveHostThermalObservation.currentLevel()
        _ = receiveMeasuredBeat(hostThermalLevel: thirdThermal, pressLoad: Self.measurePressLoad())
    }

    /// 이 맥 시계로 직전 각인 이후 경과를 잰다. 첫 각인은 박이 아니다.
    public mutating func receiveMeasuredBeat(
        hostThermalLevel: Double,
        pressLoad: Double
    ) -> Result<CognitiveFeltHeartbeat, CognitiveHeartAdmissionError> {
        let now = DispatchTime.now().uptimeNanoseconds
        guard let mark = lastClockNanoseconds else {
            lastClockNanoseconds = now
            return .failure(.noObservation)
        }
        lastClockNanoseconds = now
        guard now >= mark else {
            return .failure(.noObservation)
        }
        let seconds = Double(now - mark) / 1_000_000_000.0
        if seconds <= 0 {
            return .failure(.noObservation)
        }
        return receiveBeat(
            interval: CognitiveInterBeatInterval(seconds: seconds),
            hostThermalLevel: hostThermalLevel,
            pressLoad: pressLoad
        )
    }

    private func computeComplaints(hostThermalLevel: Double, pressLoad: Double) -> Int {
        var complaints = 0
        if let priorThermal = pressThermals.last, hostThermalLevel > priorThermal {
            complaints += 1
        }
        if let priorLoad = pressLoads.last, pressLoad > priorLoad {
            complaints += 1
        }
        return complaints
    }

    private static func trimBuffer<T>(_ buffer: inout [T], maxSize: Int) {
        let excess = buffer.count - maxSize
        guard excess > 0 else { return }
        buffer.removeFirst(excess)
    }

    private mutating func trimRingBuffers() {
        Self.trimBuffer(&intervalRNA, maxSize: Self.maxWindowSize)
        Self.trimBuffer(&pressThermals, maxSize: Self.maxWindowSize)
        Self.trimBuffer(&pressLoads, maxSize: Self.maxWindowSize)
        Self.trimBuffer(&felt, maxSize: Self.maxWindowSize)
    }

    /// 바깥에서 잰 간격만 받는다.
    public mutating func receiveBeat(
        interval: CognitiveInterBeatInterval,
        hostThermalLevel: Double,
        pressLoad: Double,
        autonomicDrive: CognitiveAutonomicToneVector? = nil
    ) -> Result<CognitiveFeltHeartbeat, CognitiveHeartAdmissionError> {
        guard interval.seconds > 0.0 && interval.seconds <= 300.0 else {
            return .failure(.noObservation)
        }
        let observed = [interval.seconds]
        let predicted = intrinsicDNA.isEmpty ? intervalRNA : intrinsicDNA
        let complaints = computeComplaints(hostThermalLevel: hostThermalLevel, pressLoad: pressLoad)
        let inverted = DynamicHomeostaticEngine.invertObserved(
            observed: observed,
            priorSamples: predicted,
            previousHash: "\(organismId).heart.\(intervalRNA.count)",
            sequenceNumber: UInt64(intervalRNA.count + 1),
            priorIntent: "\(interval.seconds)",
            complaintCount: complaints
        )
        if intrinsicDNA.isEmpty, case .closed = inverted.vessel.affect.homeostasis {
            intrinsicDNA = intervalRNA
        }
        DynamicHomeostaticEngine.assimilate(reservoir: &intervalRNA, observed: observed)
        pressThermals.append(hostThermalLevel)
        pressLoads.append(pressLoad)

        let drive = autonomicDrive ?? self.autonomicDrive
        let effectiveSeconds = drive.map {
            applyAutonomicCorrection(
                targetInterval: interval.seconds,
                autonomicDrive: $0,
                observedSurprise: inverted.vessel.affect
            )
        } ?? interval.seconds

        let beat = CognitiveFeltHeartbeat(
            interval: effectiveSeconds,
            pressThermal: hostThermalLevel,
            pressLoad: pressLoad,
            affect: inverted.vessel.affect
        )
        felt.append(beat)
        trimRingBuffers()
        _ = circulation.receiveEjection(interval: CognitiveInterBeatInterval(seconds: effectiveSeconds))
        return .success(beat)
    }

    /// 의식이 다음 박을 고르려 하면 거절한다.
    public mutating func commandBeat(
        interval _: CognitiveInterBeatInterval,
        hostThermalLevel _: Double,
        pressLoad _: Double
    ) -> Result<CognitiveFeltHeartbeat, CognitiveHeartAdmissionError> {
        .failure(.consciousnessCannotWriteBeat)
    }

    /// 호스트 하드웨어 지연시간 단일 실측 위임
    public static func measureLatency(hashRounds: Int) -> Double {
        HostHardwareTelemetry.measureLatency(hashRounds: hashRounds)
    }

    /// 호스트 하드웨어 지연시간 다회차 실측 위임
    public static func measureLatencies(hashRounds: Int, count: Int) -> [Double] {
        HostHardwareTelemetry.measureLatencies(hashRounds: hashRounds, count: count)
    }
}
