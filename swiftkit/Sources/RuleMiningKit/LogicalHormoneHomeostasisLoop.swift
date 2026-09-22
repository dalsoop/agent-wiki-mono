import Foundation

/// 루프에 넣는 한 관측. 패턴이나 RNA가 있어야 항상성 칸에 쌓인다.
public struct LogicalHormoneObservation: Sendable, Codable, Equatable {
    public let situation: String
    public let effect: String
    public let sentence: String?
    public let pattern: LogicalHormonePattern?
    public let rna: InvertedAffectVector?

    public init(
        situation: String,
        effect: String,
        sentence: String? = nil,
        pattern: LogicalHormonePattern? = nil,
        rna: InvertedAffectVector? = nil
    ) {
        self.situation = situation
        self.effect = effect
        self.sentence = sentence
        self.pattern = pattern?.isEmpty == true ? nil : pattern
        self.rna = rna
    }

    public var canStack: Bool {
        pattern != nil || rna != nil
    }
}

/// 한 번 쌓인 뒤의 항상성. 횟수 문턱이 아니라 직전 대비 상태다.
public struct LogicalHomeostasisSnapshot: Sendable, Codable, Equatable {
    public let sentence: String
    public let stackedFacts: Int
    public let stackedPatterns: Int
    public let affect: LogicalAffect?
    public let patternHolding: Bool?
    public let invertDelta: Double?

    public init(
        sentence: String,
        stackedFacts: Int,
        stackedPatterns: Int,
        affect: LogicalAffect?,
        patternHolding: Bool?,
        invertDelta: Double?
    ) {
        self.sentence = sentence
        self.stackedFacts = stackedFacts
        self.stackedPatterns = stackedPatterns
        self.affect = affect
        self.patternHolding = patternHolding
        self.invertDelta = invertDelta
    }
}

/// 관측이 오는 동안만 돈다. 같은 패턴이면 닫히고, 짝이 바뀌면 다시 열린다.
public struct LogicalHormoneHomeostasisLoop: Sendable, Equatable {
    public var world: LogicalHormoneWorld

    public init(world: LogicalHormoneWorld = LogicalHormoneWorld()) {
        self.world = world
    }

    /// 빈 관측은 쌓지 않는다. 닫혀 있어도 다음 관측은 쌓는다. 닫힘은 정지가 아니다.
    @discardableResult
    public mutating func stack(_ observation: LogicalHormoneObservation) -> LogicalHomeostasisSnapshot? {
        guard observation.canStack else { return nil }
        world.observe(
            situation: observation.situation,
            effect: observation.effect,
            sentence: observation.sentence,
            pattern: observation.pattern,
            rna: observation.rna
        )
        let claim = observation.sentence
            ?? LogicalHormoneGenome.makeSentence(situation: observation.situation, effect: observation.effect)
        return snapshot(sentence: claim)
    }

    public mutating func run<S: Sequence>(
        _ observations: S
    ) -> [LogicalHomeostasisSnapshot] where S.Element == LogicalHormoneObservation {
        observations.compactMap { stack($0) }
    }

    public func snapshot(sentence: String) -> LogicalHomeostasisSnapshot? {
        guard let gene = world.gene(sentence: sentence) else { return nil }
        let affect = gene.lastLogicalAffect
        let invertDelta: Double?
        if let predicted = gene.predictedRNA, let observed = gene.observedRNA.last {
            invertDelta = LogicalHormoneGenome.invertPredicted(
                predicted: predicted,
                observed: observed,
                history: gene.observedRNA,
                sequenceNumber: world.sequenceNumber,
                priorIntent: gene.sentence
            ).homeostaticDelta
        } else {
            invertDelta = nil
        }
        return LogicalHomeostasisSnapshot(
            sentence: gene.sentence,
            stackedFacts: gene.facts.count,
            stackedPatterns: gene.observedPatterns.count,
            affect: affect,
            patternHolding: affect?.patternShifted.map { !$0 },
            invertDelta: invertDelta
        )
    }
}
