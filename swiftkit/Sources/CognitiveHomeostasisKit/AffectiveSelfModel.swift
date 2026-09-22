import Foundation
import HomeostasisEngineKit

// MARK: - 다미주신경 3단계 진화 계층 (Polyvagal State)
/// 스티븐 포지스(Stephen W. Porges, 1995, 2007)의 다미주신경 이론에 따른 3단계 자율신경 상태.
public enum CognitivePolyvagalState: String, Sendable, Equatable, Codable, CaseIterable {
    /// 1단계: 복측 미주신경 상태 (Safe & Social Engagement)
    case ventralVagal

    /// 2단계: 교감신경 동원 상태 (Mobilization / Fight-or-Flight)
    case sympathetic

    /// 3단계: 배측 미주신경 셧다운 (Immobilization / Freeze & Somatic Veto)
    case dorsalVagal
}

// MARK: - 행동 종류
/// organism이 선택할 수 있는 행동. 정동이 이것을 결정한다.
public enum CognitiveHomeostaticAction: String, Sendable, Equatable, Codable, CaseIterable {
    /// 설정점 근처. 현재 상태를 유지한다.
    case hold
    /// V > 0, 안정. 탐색 범위를 넓힌다.
    case explore
    /// V < 0, 불안정. 마지막 닫힌 겹으로 수축한다.
    case contract
    /// 고통 기억(NegativeCache) 히트. 해당 패턴을 피한다.
    case avoid
    /// 익숙한 군집을 다시 찾는다. 패턴 반복 추구.
    case seek
}

// MARK: - 기분 (Mood)
/// 최근 N개 닫힌 창의 정동 누적. 단발 정동이 아니라 시간적 연속체.
public struct CognitiveAffectiveMood: Sendable, Equatable, Codable {
    /// 최근 valence 이동 평균
    public let valence: Double
    /// 최근 arousal 이동 평균
    public let arousal: Double
    /// 누적에 사용된 이벤트 수
    public let sampleCount: Int

    /// 기분이 행동 선택에 주는 편향. -1.0(소극)~+1.0(적극)
    public var bias: Double {
        if sampleCount < 2 { return 0.0 }
        return max(-1.0, min(1.0, valence))
    }

    public static let neutral = CognitiveAffectiveMood(valence: 0, arousal: 0, sampleCount: 0)
}

// MARK: - 자기 기준선 (Self-Baseline)
/// organism이 "내 평소"를 아는 구조. 외부 관찰자가 아니라 organism 자신이 가진다.
public struct CognitiveAffectiveSelfBaseline: Sendable, Equatable, Codable {
    public private(set) var meanValence: Double
    public private(set) var meanArousal: Double
    public private(set) var observationCount: Int

    /// 현재 정동이 기준선에서 얼마나 벗어났는지
    public func deviation(from affect: InvertedAffectVector) -> Double {
        guard observationCount >= 2 else { return 0.0 }
        let dv = affect.valence - meanValence
        let da = affect.arousal - meanArousal
        return sqrt(dv * dv + da * da)
    }

    public func deviation(from affect: HomeostaticAffect) -> Double {
        deviation(from: InvertedAffectVector(valence: affect.valence, arousal: affect.arousal, homeostaticDelta: affect.deltaH))
    }

    /// "지금 나는 평소와 다른가?"
    public func isUnusual(affect: InvertedAffectVector, threshold: Double = 0.3) -> Bool {
        deviation(from: affect) > threshold
    }

    public func isUnusual(affect: HomeostaticAffect, threshold: Double = 0.3) -> Bool {
        deviation(from: affect) > threshold
    }

    public static let empty = CognitiveAffectiveSelfBaseline(meanValence: 0, meanArousal: 0, observationCount: 0)

    /// 새 관측을 흡수한다. 지수 이동 평균.
    public mutating func absorb(valence: Double, arousal: Double) {
        observationCount += 1
        if observationCount == 1 {
            meanValence = valence
            meanArousal = arousal
            return
        }
        let alpha = max(0.002, 2.0 / Double(observationCount + 1))
        meanValence = meanValence * (1.0 - alpha) + valence * alpha
        meanArousal = meanArousal * (1.0 - alpha) + arousal * alpha
    }
}

// MARK: - 고통 기억 흔적 (Pain Memory Trace)
/// 최근 고통 기억. organism이 "아팠던 것"을 기억한다.
public struct CognitivePainMemoryTrace: Sendable, Equatable, Codable {
    public private(set) var recentPainRuleIds: [String]
    public private(set) var totalPainCount: Int
    public private(set) var meanPainValence: Double
    public let maxTraces: Int
    public private(set) var ticksSinceLastPain: Int

    public static let empty = CognitivePainMemoryTrace(
        recentPainRuleIds: [],
        totalPainCount: 0,
        meanPainValence: 0,
        maxTraces: 10,
        ticksSinceLastPain: 0
    )

    public init(
        recentPainRuleIds: [String] = [],
        totalPainCount: Int = 0,
        meanPainValence: Double = 0,
        maxTraces: Int = 10,
        ticksSinceLastPain: Int = 0
    ) {
        self.recentPainRuleIds = recentPainRuleIds
        self.totalPainCount = totalPainCount
        self.meanPainValence = meanPainValence
        self.maxTraces = maxTraces
        self.ticksSinceLastPain = ticksSinceLastPain
    }

    public mutating func recordPain(ruleId: String, painValence: Double) {
        recentPainRuleIds.append(ruleId)
        if recentPainRuleIds.count > maxTraces {
            recentPainRuleIds.removeFirst()
        }
        totalPainCount += 1
        ticksSinceLastPain = 0
        let alpha = max(0.1, 2.0 / Double(totalPainCount + 1))
        meanPainValence = meanPainValence * (1.0 - alpha) + painValence * alpha
    }

    public mutating func decayTick() {
        ticksSinceLastPain += 1
        if ticksSinceLastPain > 15 && !recentPainRuleIds.isEmpty {
            recentPainRuleIds.removeFirst()
            meanPainValence *= 0.8
        }
    }

    public var hasRecentPain: Bool {
        !recentPainRuleIds.isEmpty && ticksSinceLastPain <= 30
    }

    public func isKnownPain(ruleId: String) -> Bool {
        recentPainRuleIds.contains(ruleId)
    }
}

// MARK: - 군집 친숙도 (Cluster Familiarity)
public struct CognitiveClusterFamiliarity: Sendable, Equatable, Codable {
    public private(set) var dominantClusterId: String?
    public private(set) var clusterHitCounts: [String: Int]
    public private(set) var totalPlacements: Int

    public static let empty = CognitiveClusterFamiliarity(dominantClusterId: nil, clusterHitCounts: [:], totalPlacements: 0)

    public mutating func recordPlacement(clusterId: String) {
        totalPlacements += 1
        clusterHitCounts[clusterId, default: 0] += 1
        if let dominant = dominantClusterId {
            let dominantCount = clusterHitCounts[dominant, default: 0]
            let currentCount = clusterHitCounts[clusterId, default: 0]
            if currentCount > dominantCount {
                dominantClusterId = clusterId
            }
        } else {
            dominantClusterId = clusterId
        }
    }

    public func isFamiliar(clusterId: String) -> Bool {
        (clusterHitCounts[clusterId] ?? 0) >= 2
    }

    public var hasDominantPattern: Bool {
        guard let d = dominantClusterId else { return false }
        return (clusterHitCounts[d] ?? 0) >= 3
    }
}

// MARK: - 호기심 드라이브 (Curiosity & Epistemic Seeking Drive)
public struct CognitiveCuriosityDrive: Sendable, Equatable, Codable {
    public private(set) var currentCuriosityScore: Double
    public private(set) var totalChallengesEncountered: Int
    public private(set) var masteredRuleIds: [String]
    public private(set) var quenchRefractoryTicksLeft: Int

    public static let empty = CognitiveCuriosityDrive(
        currentCuriosityScore: 0.0,
        totalChallengesEncountered: 0,
        masteredRuleIds: [],
        quenchRefractoryTicksLeft: 0
    )

    public init(
        currentCuriosityScore: Double = 0.0,
        totalChallengesEncountered: Int = 0,
        masteredRuleIds: [String] = [],
        quenchRefractoryTicksLeft: Int = 0
    ) {
        self.currentCuriosityScore = currentCuriosityScore
        self.totalChallengesEncountered = totalChallengesEncountered
        self.masteredRuleIds = masteredRuleIds
        self.quenchRefractoryTicksLeft = quenchRefractoryTicksLeft
    }

    public mutating func evaluateNovelty(novelty: Double) -> Double {
        if quenchRefractoryTicksLeft > 0 {
            quenchRefractoryTicksLeft -= 1
            currentCuriosityScore = 0.0
            return 0.0
        }
        totalChallengesEncountered += 1
        let score: Double
        if novelty < 0.15 {
            score = 0.05
        } else if novelty <= 0.85 {
            score = min(1.0, 0.35 + (novelty - 0.15) * 0.9)
        } else {
            score = max(0.0, 1.0 - (novelty - 0.85) * 5.0)
        }
        currentCuriosityScore = score
        return score
    }

    public mutating func recordMastery(ruleId: String) {
        if !masteredRuleIds.contains(ruleId) {
            masteredRuleIds.append(ruleId)
        }
        currentCuriosityScore = 0.0
    }

    public mutating func quench(refractoryTicks: Int = 10) {
        currentCuriosityScore = 0.0
        quenchRefractoryTicksLeft = refractoryTicks
    }

    public mutating func decayRefractory() {
        if quenchRefractoryTicksLeft > 0 {
            quenchRefractoryTicksLeft -= 1
        }
    }

    public func isMastered(ruleId: String) -> Bool {
        masteredRuleIds.contains(ruleId)
    }
}

// MARK: - 자기 모델 (AffectiveSelfModel)
public struct CognitiveAffectiveSelfModel: Sendable, Equatable, Codable {
    public private(set) var baseline: CognitiveAffectiveSelfBaseline
    public let moodWindowSize: Int
    var recentValences: [Double]
    var recentArousals: [Double]
    public private(set) var lastAction: CognitiveHomeostaticAction
    public private(set) var actionTransitionCount: Int
    public private(set) var endogenousCount: Int
    public private(set) var exogenousCount: Int
    public var painMemory: CognitivePainMemoryTrace
    public var clusterFamiliarity: CognitiveClusterFamiliarity
    public var curiosity: CognitiveCuriosityDrive
    public var polyvagalState: CognitivePolyvagalState
    var sympatheticRecoveryTicksLeft: Int

    public init(moodWindowSize: Int = 10) {
        self.baseline = .empty
        self.moodWindowSize = moodWindowSize
        self.recentValences = []
        self.recentArousals = []
        self.lastAction = .hold
        self.actionTransitionCount = 0
        self.endogenousCount = 0
        self.exogenousCount = 0
        self.painMemory = .empty
        self.clusterFamiliarity = .empty
        self.curiosity = .empty
        self.polyvagalState = .ventralVagal
        self.sympatheticRecoveryTicksLeft = 0
    }

    private mutating func trimRecentWindows() {
        guard recentValences.count > moodWindowSize else { return }
        recentValences.removeFirst()
        recentArousals.removeFirst()
    }

    private mutating func updatePolyvagalRecovery() {
        if sympatheticRecoveryTicksLeft > 0 {
            sympatheticRecoveryTicksLeft -= 1
        }
        guard !painMemory.hasRecentPain else { return }
        switch polyvagalState {
        case .dorsalVagal:
            polyvagalState = .sympathetic
            sympatheticRecoveryTicksLeft = 10
        case .sympathetic where sympatheticRecoveryTicksLeft == 0:
            polyvagalState = .ventralVagal
        default:
            break
        }
    }

    public mutating func observe(affect: InvertedAffectVector, origin: CognitiveAffectOrigin = .endogenous) {
        baseline.absorb(valence: affect.valence, arousal: affect.arousal)
        recentValences.append(affect.valence)
        recentArousals.append(affect.arousal)
        trimRecentWindows()
        switch origin {
        case .endogenous: endogenousCount += 1
        case .exogenous: exogenousCount += 1
        }
        painMemory.decayTick()
        curiosity.decayRefractory()
        updatePolyvagalRecovery()
    }

    public mutating func observe(affect: HomeostaticAffect, origin: CognitiveAffectOrigin = .endogenous) {
        observe(affect: InvertedAffectVector(valence: affect.valence, arousal: affect.arousal, homeostaticDelta: affect.deltaH), origin: origin)
    }

    private mutating func handleImmobilizationContract() -> CognitiveHomeostaticAction {
        polyvagalState = .dorsalVagal
        sympatheticRecoveryTicksLeft = 10
        curiosity.quench(refractoryTicks: 10)
        if lastAction != .contract {
            actionTransitionCount += 1
        }
        lastAction = .contract
        return .contract
    }

    public mutating func selectAction(currentAffect: InvertedAffectVector) -> CognitiveHomeostaticAction {
        let state = currentPolyvagalState
        let isImmobilized = (state == .dorsalVagal) && painMemory.hasRecentPain && (currentAffect.arousal <= 0.2)
        if isImmobilized {
            return handleImmobilizationContract()
        }
        if polyvagalState == .dorsalVagal {
            polyvagalState = .sympathetic
            sympatheticRecoveryTicksLeft = 10
        }

        let mood = computeMood()
        let effectiveValence = currentAffect.valence + mood.bias * 0.3

        let action: CognitiveHomeostaticAction
        switch true {
        case curiosity.currentCuriosityScore > 0.3 && effectiveValence >= -0.1:
            action = .seek
        case painMemory.hasRecentPain && effectiveValence < 0:
            action = .avoid
        case effectiveValence < -0.6:
            action = .contract
        case clusterFamiliarity.hasDominantPattern && effectiveValence > 0.2 && currentAffect.arousal < 0.4:
            action = .seek
        case effectiveValence < -0.25:
            action = .contract
        case effectiveValence > 0.3 && currentAffect.arousal < 0.7:
            action = .explore
        default:
            action = .hold
        }

        return updateLastAction(action)
    }

    private mutating func updateLastAction(_ action: CognitiveHomeostaticAction) -> CognitiveHomeostaticAction {
        if action != lastAction {
            actionTransitionCount += 1
        }
        lastAction = action
        return action
    }

    public var currentPolyvagalState: CognitivePolyvagalState {
        if polyvagalState == .dorsalVagal {
            return .dorsalVagal
        }
        if painMemory.hasRecentPain {
            let isSevereTrauma = painMemory.meanPainValence <= -0.94
            let isOverloaded = painMemory.recentPainRuleIds.count >= 4
            if isSevereTrauma || isOverloaded {
                return .dorsalVagal
            }
        }
        if sympatheticRecoveryTicksLeft > 0 {
            return .sympathetic
        }
        let isDefensiveAction = (lastAction == .avoid || lastAction == .contract)
        if painMemory.hasRecentPain || isDefensiveAction {
            return .sympathetic
        }
        return .ventralVagal
    }

    public var curiosityNoveltyScore: Double {
        curiosity.currentCuriosityScore
    }

    public mutating func receivePain(val: Double, ruleId: String = "pain_stimulus") {
        recordPain(ruleId: ruleId, painValence: val)
        if currentPolyvagalState == .dorsalVagal {
            polyvagalState = .dorsalVagal
            sympatheticRecoveryTicksLeft = 10
            curiosity.quench(refractoryTicks: 10)
        }
    }

    public mutating func forceDorsalShutdown() {
        polyvagalState = .dorsalVagal
        sympatheticRecoveryTicksLeft = 10
        curiosity.quench(refractoryTicks: 10)
        if lastAction != .contract {
            actionTransitionCount += 1
        }
        lastAction = .contract
    }

    public mutating func transitionPolyvagalState(to newState: CognitivePolyvagalState) {
        self.polyvagalState = newState
        switch newState {
        case .ventralVagal:
            self.sympatheticRecoveryTicksLeft = 0
        case .sympathetic:
            self.sympatheticRecoveryTicksLeft = 10
        case .dorsalVagal:
            forceDorsalShutdown()
        }
    }

    public var endogenousRatio: Double {
        let total = endogenousCount + exogenousCount
        guard total > 0 else { return 0 }
        return Double(endogenousCount) / Double(total)
    }

    public var summary: CognitiveSelfModelSummary {
        CognitiveSelfModelSummary(
            baseline: baseline,
            mood: computeMood(),
            lastAction: lastAction,
            actionTransitionCount: actionTransitionCount,
            endogenousRatio: endogenousRatio,
            totalObservations: baseline.observationCount,
            totalPainCount: painMemory.totalPainCount,
            dominantClusterId: clusterFamiliarity.dominantClusterId,
            hasDominantPattern: clusterFamiliarity.hasDominantPattern
        )
    }

    public mutating func selectAction(currentAffect: HomeostaticAffect) -> CognitiveHomeostaticAction {
        let inverted = InvertedAffectVector(
            valence: currentAffect.valence,
            arousal: currentAffect.arousal,
            homeostaticDelta: currentAffect.deltaH
        )
        return selectAction(currentAffect: inverted)
    }

    public mutating func selectAction() -> CognitiveHomeostaticAction {
        let defaultAffect = InvertedAffectVector(
            valence: baseline.meanValence,
            arousal: baseline.meanArousal,
            homeostasis: .opened
        )
        return selectAction(currentAffect: defaultAffect)
    }

    public func computeMood() -> CognitiveAffectiveMood {
        guard !recentValences.isEmpty else { return .neutral }
        let n = Double(recentValences.count)
        let avgV = recentValences.reduce(0, +) / n
        let avgA = recentArousals.reduce(0, +) / n
        return CognitiveAffectiveMood(valence: avgV, arousal: avgA, sampleCount: recentValences.count)
    }

    public mutating func recordPain(ruleId: String, painValence: Double) {
        painMemory.recordPain(ruleId: ruleId, painValence: painValence)
    }

    public mutating func recordClusterPlacement(clusterId: String) {
        clusterFamiliarity.recordPlacement(clusterId: clusterId)
    }

    @discardableResult
    public mutating func evaluateCuriosity(novelty: Double) -> Double {
        curiosity.evaluateNovelty(novelty: novelty)
    }

    public mutating func recordMastery(ruleId: String) {
        curiosity.recordMastery(ruleId: ruleId)
    }

    public mutating func soothe(valenceBoost: Double = 0.5) {
        let currentV = recentValences.last ?? 0.0
        let currentA = recentArousals.last ?? 0.0
        let calmAffect = InvertedAffectVector(
            valence: min(1.0, currentV + valenceBoost),
            arousal: max(0.0, currentA - 0.2),
            homeostaticDelta: 0.05
        )
        observe(affect: calmAffect, origin: .exogenous)
        polyvagalState = .ventralVagal
        sympatheticRecoveryTicksLeft = 0
    }

    public func isUnusual(affect: InvertedAffectVector) -> Bool {
        baseline.isUnusual(affect: affect)
    }

    public func isUnusual(affect: HomeostaticAffect) -> Bool {
        baseline.isUnusual(affect: affect)
    }
}

public enum CognitiveAffectOrigin: String, Sendable, Codable {
    case endogenous
    case exogenous
}

public struct CognitiveSelfModelSummary: Sendable, Equatable {
    public let baseline: CognitiveAffectiveSelfBaseline
    public let mood: CognitiveAffectiveMood
    public let lastAction: CognitiveHomeostaticAction
    public let actionTransitionCount: Int
    public let endogenousRatio: Double
    public let totalObservations: Int
    public let totalPainCount: Int
    public let dominantClusterId: String?
    public let hasDominantPattern: Bool
}
