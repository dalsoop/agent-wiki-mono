import Foundation
import CryptoKit

// MARK: - 1. 시냅스 태그 상태 (Early-LTP 자격 흔적)

public struct SynapticTag: Sendable, Codable, Equatable {
    public let linkId: String
    public let sourcePatternId: String
    public let targetPatternId: String
    public var traceAmplitude: Double          // 초기 자격 흔적 강도 (0.0 ... 1.0)
    public let taggedAt: Date
    public let tagHalfLifeSeconds: Double      // 관측 윈도우 및 항상성 델타로부터 유도된 반감기
    public let triggerDeltaH: Double           // 태깅 유발 시점의 항상성 델타
    public let triggerValence: Double          // 태깅 유발 시점의 정동 가치

    public init(
        linkId: String,
        sourcePatternId: String,
        targetPatternId: String,
        traceAmplitude: Double,
        taggedAt: Date,
        tagHalfLifeSeconds: Double,
        triggerDeltaH: Double,
        triggerValence: Double
    ) {
        self.linkId = linkId
        self.sourcePatternId = sourcePatternId
        self.targetPatternId = targetPatternId
        self.traceAmplitude = traceAmplitude
        self.taggedAt = taggedAt
        self.tagHalfLifeSeconds = tagHalfLifeSeconds
        self.triggerDeltaH = triggerDeltaH
        self.triggerValence = triggerValence
    }

    /// 경과 시간에 따른 지수 감쇠 잔존 자격 강도 계산 (Closed-Form)
    public func currentTrace(at currentTime: Date) -> Double {
        let elapsed = max(0.0, currentTime.timeIntervalSince(taggedAt))
        let lambda = log(2.0) / max(Double.ulpOfOne, tagHalfLifeSeconds)
        return traceAmplitude * exp(-lambda * elapsed)
    }
}

// MARK: - 2. 항상성 결합 링크 (Homeostatic Binding Link)

public struct HomeostaticBindingLink: Sendable, Codable, Equatable {
    public let linkId: String
    public let sourcePatternId: String
    public let targetPatternId: String
    public let coordId: String
    public let entityId: String
    public var consolidatedWeight: Double      // Late-LTP에 의해 고착된 장기 가중치
    public var activeTag: SynapticTag?          // Early-LTP 임시 마킹 자격 흔적
    public var activationCount: Int
    public var lastUpdated: Date

    public init(
        linkId: String,
        sourcePatternId: String,
        targetPatternId: String,
        coordId: String? = nil,
        entityId: String? = nil,
        consolidatedWeight: Double,
        activeTag: SynapticTag? = nil,
        activationCount: Int = 1,
        lastUpdated: Date = Date()
    ) {
        self.linkId = linkId
        self.sourcePatternId = sourcePatternId
        self.targetPatternId = targetPatternId
        self.coordId = coordId ?? sourcePatternId
        self.entityId = entityId ?? targetPatternId
        self.consolidatedWeight = consolidatedWeight
        self.activeTag = activeTag
        self.activationCount = activationCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - 3. 온라인 시냅스 태깅 엔진 프로토콜

public protocol OnlineSynapticTaggingEngineProtocol: Sendable {
    func evaluateAndTag(
        vessel: NarrativeConsciousnessVessel,
        activeLinks: [HomeostaticBindingLink]
    ) -> [HomeostaticBindingLink]
}

// MARK: - 4. 하드코딩 0% Early-LTP 적격성 엔진 구현체

public struct EarlyLTPEligibilityEngine: OnlineSynapticTaggingEngineProtocol, Sendable {
    public init() {}

    public func evaluateAndTag(
        vessel: NarrativeConsciousnessVessel,
        activeLinks: [HomeostaticBindingLink]
    ) -> [HomeostaticBindingLink] {
        guard case .closed(let deltaH) = vessel.affect.homeostasis else {
            return activeLinks
        }
        let baseline = vessel.baselineMetrics
        let telemetry = vessel.telemetrySnapshot

        // 윈도우 관측 시간 (ms 단위가 아닌 실측 초 단위, 0 분모 방지 Double.ulpOfOne)
        let windowDurationSec = max(Double.ulpOfOne, telemetry.windowEndTime.timeIntervalSince(telemetry.windowStartTime))

        // 동적 임계치 도출: baselineSigma 및 baseline Spread 기반 (매직 넘버 0%)
        let errorThreshold = baseline.baselineSigma
        let rewardDenominator = max(Double.ulpOfOne, baseline.baselineMean)
        let rewardThreshold = baseline.baselineMean > 0.0 ? (baseline.baselineP95 - baseline.baselineMean) / rewardDenominator : 0.0

        let isExtremeError = deltaH > errorThreshold
        let isStrongReward = vessel.affect.valence > rewardThreshold

        // 자격 흔적 반감기 닫힌 해: 윈도우 관측 시간과 항상성 변동 비율 결합
        let effectiveSigma = max(Double.ulpOfOne, baseline.baselineSigma)
        let dynamicHalfLife = windowDurationSec * (1.0 + (deltaH / effectiveSigma))

        // 초기 자격 강도 도출: 델타 오차와 Arousal의 정규화 결합치
        let rawTrace = min(1.0, (deltaH / effectiveSigma) * (vessel.affect.arousal + Double.ulpOfOne))
        let initialAmplitude = max(Double.ulpOfOne, rawTrace)

        let now = telemetry.windowEndTime
        let pruneEpsilon = Double.ulpOfOne

        return activeLinks.map { link in
            var updatedLink = link
            updatedLink.lastUpdated = now
            updatedLink.activationCount += 1

            if isExtremeError || isStrongReward {
                let tag = SynapticTag(
                    linkId: link.linkId,
                    sourcePatternId: link.sourcePatternId,
                    targetPatternId: link.targetPatternId,
                    traceAmplitude: initialAmplitude,
                    taggedAt: now,
                    tagHalfLifeSeconds: dynamicHalfLife,
                    triggerDeltaH: deltaH,
                    triggerValence: vessel.affect.valence
                )
                updatedLink.activeTag = tag
            } else if let existingTag = updatedLink.activeTag {
                // 트리거 조건 미달 시 경과 감쇠 반영
                let currentStrength = existingTag.currentTrace(at: now)
                if currentStrength <= pruneEpsilon {
                    updatedLink.activeTag = nil
                }
            }
            return updatedLink
        }
    }
}
