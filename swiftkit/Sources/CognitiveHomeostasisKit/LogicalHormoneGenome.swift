import Foundation
import CryptoKit

// MARK: - 1. 논리 호르몬 발현 (LogicalHormoneRNA)
/// 논리 호르몬 발현. 계수가 아니라 invert 정동 세 수다.
public struct LogicalHormoneRNA: Sendable, Codable, Equatable {
    public let affect: InvertedAffectVector
    public let expressedAt: Date

    public init(affect: InvertedAffectVector, expressedAt: Date = Date()) {
        self.affect = affect
        self.expressedAt = expressedAt
    }
}

// MARK: - 2. 논리 호르몬 채널 및 대조
public enum LogicalHormoneChannel: String, Sendable, Codable, CaseIterable, Comparable {
    case dopamine
    case noradrenaline
    case adrenaline
    case cortisol
    case oxytocin
    case vasopressin

    public static func < (lhs: LogicalHormoneChannel, rhs: LogicalHormoneChannel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isCatecholamine: Bool {
        switch self {
        case .dopamine, .noradrenaline, .adrenaline:
            return true
        default:
            return false
        }
    }
}

public enum LogicalHormoneMotion: String, Sendable, Codable, Equatable {
    case rose
    case fell
    case held
}

public enum LogicalHormonePairRelation: String, Sendable, Codable, Equatable {
    case sameDirection
    case opposed
    case oneHeld
}

public struct LogicalHormonePairContrast: Sendable, Codable, Equatable, Hashable {
    public let left: LogicalHormoneChannel
    public let right: LogicalHormoneChannel
    public let relation: LogicalHormonePairRelation

    public init(left: LogicalHormoneChannel, right: LogicalHormoneChannel, relation: LogicalHormonePairRelation) {
        if left <= right {
            self.left = left
            self.right = right
        } else {
            self.left = right
            self.right = left
        }
        self.relation = relation
    }
}

public struct LogicalHormonePattern: Sendable, Codable, Equatable {
    public let motions: [LogicalHormoneChannel: LogicalHormoneMotion]

    public init(motions: [LogicalHormoneChannel: LogicalHormoneMotion]) {
        self.motions = motions
    }

    public var isEmpty: Bool { motions.isEmpty }

    public subscript(channel: LogicalHormoneChannel) -> LogicalHormoneMotion? {
        motions[channel]
    }

    public var pairContrasts: [LogicalHormonePairContrast] {
        let sortedChannels = LogicalHormoneChannel.allCases.filter { motions[$0] != nil }
        var result: [LogicalHormonePairContrast] = []
        for i in 0..<sortedChannels.count {
            for j in (i + 1)..<sortedChannels.count {
                let left = sortedChannels[i]
                let right = sortedChannels[j]
                guard let mLeft = motions[left], let mRight = motions[right] else { continue }
                let rel: LogicalHormonePairRelation
                if mLeft == .held || mRight == .held {
                    rel = .oneHeld
                } else if mLeft == mRight {
                    rel = .sameDirection
                } else {
                    rel = .opposed
                }
                result.append(LogicalHormonePairContrast(left: left, right: right, relation: rel))
            }
        }
        return result
    }

    public var catecholamineRose: Bool {
        LogicalHormoneChannel.allCases
            .filter(\.isCatecholamine)
            .compactMap { motions[$0] }
            .contains(.rose)
    }

    public var catecholamineFellWithoutRise: Bool {
        let catMotions = LogicalHormoneChannel.allCases
            .filter(\.isCatecholamine)
            .compactMap { motions[$0] }
        return catMotions.contains(.fell) && !catMotions.contains(.rose)
    }
}

public enum LogicalAffectPolarity: String, Sendable, Codable, Equatable {
    case consonant
    case dissonant
}

public enum LogicalAffectAlert: String, Sendable, Codable, Equatable {
    case raised
    case lowered
}

public struct LogicalAffect: Sendable, Codable, Equatable {
    public let polarity: LogicalAffectPolarity?
    public let alert: LogicalAffectAlert?
    public let patternShifted: Bool?
    public let pairs: [LogicalHormonePairContrast]

    public init(
        polarity: LogicalAffectPolarity?,
        alert: LogicalAffectAlert?,
        patternShifted: Bool? = nil,
        pairs: [LogicalHormonePairContrast]
    ) {
        self.polarity = polarity
        self.alert = alert
        self.patternShifted = patternShifted
        self.pairs = pairs
    }
}

public enum LogicalHormoneContrast {
    public static func makeAffect(
        observed: LogicalHormonePattern,
        predicted: LogicalHormonePattern? = nil
    ) -> LogicalAffect? {
        let pairs = observed.pairContrasts
        guard !pairs.isEmpty else { return nil }
        return LogicalAffect(
            polarity: polarity(of: observed),
            alert: alert(of: observed),
            patternShifted: shift(observed: observed, predicted: predicted),
            pairs: pairs
        )
    }

    private static func alert(of pattern: LogicalHormonePattern) -> LogicalAffectAlert? {
        if pattern.catecholamineRose { return .raised }
        if pattern.catecholamineFellWithoutRise { return .lowered }
        return nil
    }

    private static func polarity(of pattern: LogicalHormonePattern) -> LogicalAffectPolarity? {
        switch pattern[.cortisol] {
        case .rose:
            return .dissonant
        case .fell:
            return pattern[.oxytocin] == .rose ? .consonant : (pattern.catecholamineFellWithoutRise ? .dissonant : nil)
        default:
            return nil
        }
    }

    private static func shift(
        observed: LogicalHormonePattern,
        predicted: LogicalHormonePattern?
    ) -> Bool? {
        guard let predicted else { return nil }
        let observedPairs = Set(observed.pairContrasts)
        let predictedPairs = Set(predicted.pairContrasts)
        guard !observedPairs.isEmpty, !predictedPairs.isEmpty else { return nil }
        return observedPairs != predictedPairs
    }
}

// MARK: - 3. 한 상황의 논리 사실 (LogicalHormoneFact)
public struct LogicalHormoneFact: Sendable, Codable, Equatable {
    public let sentence: String
    public let effect: String
    public let pattern: LogicalHormonePattern?
    public let rna: InvertedAffectVector?
    public let recordedAt: Date

    public init(
        sentence: String,
        effect: String,
        pattern: LogicalHormonePattern? = nil,
        rna: InvertedAffectVector? = nil,
        recordedAt: Date = Date()
    ) {
        self.sentence = sentence
        self.effect = effect
        self.pattern = pattern?.isEmpty == true ? nil : pattern
        self.rna = rna
        self.recordedAt = recordedAt
    }

    public var logicalAffect: LogicalAffect? {
        guard let pattern else { return nil }
        return LogicalHormoneContrast.makeAffect(observed: pattern)
    }
}

// MARK: - 4. 상황 → 논리 법칙 (LogicalHormoneDNA)
public struct LogicalHormoneDNA: Sendable, Codable, Equatable {
    public let situationKey: String
    public let situation: String
    public let sentence: String
    public let effect: String
    public let putPrior: InvertedAffectVector?
    public let facts: [LogicalHormoneFact]

    public init(
        situationKey: String,
        situation: String,
        sentence: String,
        effect: String,
        putPrior: InvertedAffectVector?,
        facts: [LogicalHormoneFact]
    ) {
        self.situationKey = situationKey
        self.situation = situation
        self.sentence = sentence
        self.effect = effect
        self.putPrior = putPrior
        self.facts = facts
    }

    public var observedRNA: [InvertedAffectVector] {
        facts.compactMap(\.rna)
    }

    public var predictedRNA: InvertedAffectVector? {
        LogicalHormoneGenome.meanRNA(([putPrior].compactMap { $0 }) + observedRNA)
    }

    public var canEvaluatePlacement: Bool {
        !effect.isEmpty && predictedRNA != nil && observedRNA.last != nil
    }

    public var observedPatterns: [LogicalHormonePattern] {
        facts.compactMap(\.pattern)
    }

    public var lastPattern: LogicalHormonePattern? {
        observedPatterns.last
    }

    public var lastLogicalAffect: LogicalAffect? {
        guard let observed = lastPattern else { return nil }
        let predicted = observedPatterns.dropLast().last
        return LogicalHormoneContrast.makeAffect(observed: observed, predicted: predicted)
    }
}

// MARK: - 5. 티어 행 및 호르몬 모델
public struct LogicalHormoneTierRow: Sendable, Codable, Equatable {
    public let sentence: String
    public let situation: String
    public let effect: String
    public let position: Int
    public let predicted: InvertedAffectVector?
    public let placementInvert: InvertedAffectVector?
    public let neighborInvert: InvertedAffectVector?
    public let belongsAtPosition: Bool?

    public init(
        sentence: String,
        situation: String,
        effect: String,
        position: Int,
        predicted: InvertedAffectVector?,
        placementInvert: InvertedAffectVector?,
        neighborInvert: InvertedAffectVector?,
        belongsAtPosition: Bool?
    ) {
        self.sentence = sentence
        self.situation = situation
        self.effect = effect
        self.position = position
        self.predicted = predicted
        self.placementInvert = placementInvert
        self.neighborInvert = neighborInvert
        self.belongsAtPosition = belongsAtPosition
    }
}

public struct LogicalHormone: Sendable, Codable, Equatable {
    public let sentence: String
    public let memberSentences: [String]
    public let expressed: InvertedAffectVector
    public let lastObserved: InvertedAffectVector
    public let homeostasis: InvertedAffectVector
    public let observationCount: Int

    public init(
        sentence: String,
        memberSentences: [String],
        expressed: InvertedAffectVector,
        lastObserved: InvertedAffectVector,
        homeostasis: InvertedAffectVector,
        observationCount: Int
    ) {
        self.sentence = sentence
        self.memberSentences = memberSentences
        self.expressed = expressed
        self.lastObserved = lastObserved
        self.homeostasis = homeostasis
        self.observationCount = observationCount
    }
}

// MARK: - 6. 유전체 역산 엔진 (LogicalHormoneGenome)
public enum LogicalHormoneGenome {
    public static func situationKey(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func makeSentence(situation: String, effect: String) -> String {
        let sit = situation.trimmingCharacters(in: .whitespacesAndNewlines)
        let eff = effect.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!sit.isEmpty, "logical sentence requires a situation")
        precondition(!eff.isEmpty, "logical sentence requires an effect")
        return "\(sit) 때 \(eff)"
    }

    public static func makeDNA(
        situation: String,
        effect: String = "",
        sentence: String? = nil,
        predicted: InvertedAffectVector? = nil
    ) -> LogicalHormoneDNA {
        let claim: String
        if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            claim = sentence
        } else if !effect.isEmpty {
            claim = makeSentence(situation: situation, effect: effect)
        } else {
            claim = situation
        }
        return LogicalHormoneDNA(
            situationKey: situationKey(claim),
            situation: situation,
            sentence: claim,
            effect: effect,
            putPrior: predicted,
            facts: []
        )
    }

    public static func makeRNA(_ affect: InvertedAffectVector, expressedAt: Date = Date()) -> LogicalHormoneRNA {
        LogicalHormoneRNA(affect: affect, expressedAt: expressedAt)
    }

    public static func meanRNA(_ items: [InvertedAffectVector]) -> InvertedAffectVector? {
        guard !items.isEmpty else { return nil }
        let n = Double(items.count)
        return InvertedAffectVector(
            valence: items.map(\.valence).reduce(0, +) / n,
            arousal: items.map(\.arousal).reduce(0, +) / n,
            homeostaticDelta: items.map(\.homeostaticDelta).reduce(0, +) / n
        )
    }

    public static func invertPredicted(
        predicted: InvertedAffectVector,
        observed: InvertedAffectVector,
        history: [InvertedAffectVector],
        sequenceNumber: UInt64,
        priorIntent: String
    ) -> InvertedAffectVector {
        let samples = [observed.valence, observed.arousal, observed.homeostaticDelta]
        let preds = [predicted.valence, predicted.arousal, predicted.homeostaticDelta]
        let baseline = strata(predicted: predicted, history: history)
        return NarrativeConsciousnessVessel.invert(
            sequenceNumber: sequenceNumber,
            previousHash: situationKey(priorIntent),
            priorIntent: priorIntent,
            telemetry: ThreeSecondTelemetryWindow(
                latencySamples: samples,
                predictedLatencies: preds
            ),
            baseline: baseline
        ).affect
    }

    public static func strata(
        predicted: InvertedAffectVector,
        history: [InvertedAffectVector]
    ) -> StrataBaselineMetrics {
        strata(
            predictedChannels: [predicted.valence, predicted.arousal, predicted.homeostaticDelta],
            historyChannels: history.flatMap { [$0.valence, $0.arousal, $0.homeostaticDelta] }
        )
    }

    public static func strata(
        predictedChannels: [Double],
        historyChannels: [Double]
    ) -> StrataBaselineMetrics {
        precondition(!predictedChannels.isEmpty, "strata requires predicted channels")
        let baselineMean = predictedChannels.reduce(0, +) / Double(predictedChannels.count)
        let baselineP95 = predictedChannels.max() ?? baselineMean
        let sigma: Double
        if historyChannels.count >= 2 {
            let mu = historyChannels.reduce(0, +) / Double(historyChannels.count)
            let variance = historyChannels.map { ($0 - mu) * ($0 - mu) }.reduce(0, +) / Double(historyChannels.count)
            sigma = sqrt(variance)
        } else {
            sigma = Double.ulpOfOne
        }
        return StrataBaselineMetrics(
            baselineMean: baselineMean,
            baselineP95: max(baselineP95, baselineMean),
            baselineSigma: max(Double.ulpOfOne, sigma)
        )
    }
}

// MARK: - 7. 논리 호르몬 월드 (LogicalHormoneWorld)
public struct LogicalHormoneWorld: Sendable, Equatable {
    public private(set) var genes: [String: LogicalHormoneDNA]
    public private(set) var sequenceNumber: UInt64

    public init(genes: [String: LogicalHormoneDNA] = [:], sequenceNumber: UInt64 = 0) {
        self.genes = genes
        self.sequenceNumber = sequenceNumber
    }

    public mutating func putPredicted(
        situation: String,
        sentence: String? = nil,
        rna: InvertedAffectVector
    ) {
        let claim = sentence ?? situation
        let key = LogicalHormoneGenome.situationKey(claim)
        let existing = genes[key]
        genes[key] = LogicalHormoneDNA(
            situationKey: key,
            situation: existing?.situation ?? situation,
            sentence: existing?.sentence ?? claim,
            effect: existing?.effect ?? "",
            putPrior: rna,
            facts: existing?.facts ?? []
        )
        sequenceNumber += 1
    }

    public mutating func observe(
        situation: String,
        effect: String,
        sentence: String? = nil,
        pattern: LogicalHormonePattern? = nil,
        rna: InvertedAffectVector? = nil
    ) {
        let claim = sentence ?? LogicalHormoneGenome.makeSentence(situation: situation, effect: effect)
        let key = LogicalHormoneGenome.situationKey(claim)
        let existing = genes[key]
        let situationPrior = genes[LogicalHormoneGenome.situationKey(situation)]
        var facts = existing?.facts ?? []
        facts.append(LogicalHormoneFact(sentence: claim, effect: effect, pattern: pattern, rna: rna))
        genes[key] = LogicalHormoneDNA(
            situationKey: key,
            situation: existing?.situation ?? situation,
            sentence: claim,
            effect: effect,
            putPrior: existing?.putPrior ?? situationPrior?.putPrior,
            facts: facts
        )
        sequenceNumber += 1
    }

    public func logicalAffect(sentence: String) -> LogicalAffect? {
        gene(sentence: sentence)?.lastLogicalAffect
    }

    public func predict(situation: String) -> InvertedAffectVector? {
        let situationKey = LogicalHormoneGenome.situationKey(situation)
        let matching = genes.values.filter { $0.situationKey == situationKey || $0.situation == situation }
        if let withObs = matching.first(where: { !$0.observedRNA.isEmpty })?.predictedRNA {
            return withObs
        }
        if let exact = genes[situationKey]?.predictedRNA {
            return exact
        }
        return matching.first?.predictedRNA
    }

    public func gene(sentence: String) -> LogicalHormoneDNA? {
        genes[LogicalHormoneGenome.situationKey(sentence)]
    }

    public func gene(_ situation: String) -> LogicalHormoneDNA? {
        if let exact = genes[LogicalHormoneGenome.situationKey(situation)] {
            return exact
        }
        return genes.values.first { $0.situation == situation }
    }

    public func worldHomeostasis() -> InvertedAffectVector? {
        var samples: [Double] = []
        var preds: [Double] = []
        var history: [InvertedAffectVector] = []
        var predictedVectors: [InvertedAffectVector] = []
        for gene in genes.values {
            guard let pred = gene.predictedRNA, let last = gene.observedRNA.last else { continue }
            samples.append(contentsOf: [last.valence, last.arousal, last.homeostaticDelta])
            preds.append(contentsOf: [pred.valence, pred.arousal, pred.homeostaticDelta])
            history.append(contentsOf: gene.observedRNA)
            predictedVectors.append(pred)
        }
        guard let predicted = LogicalHormoneGenome.meanRNA(predictedVectors), !samples.isEmpty else { return nil }
        let baseline = LogicalHormoneGenome.strata(predicted: predicted, history: history)
        return NarrativeConsciousnessVessel.invert(
            sequenceNumber: sequenceNumber,
            previousHash: "logical-hormone-world",
            priorIntent: "world-homeostasis",
            telemetry: ThreeSecondTelemetryWindow(
                latencySamples: samples,
                predictedLatencies: preds
            ),
            baseline: baseline
        ).affect
    }

    public func tierList() -> [LogicalHormoneTierRow] {
        let ranked = genes.values.sorted { lhs, rhs in
            let left = lhs.predictedRNA?.arousal ?? -1
            let right = rhs.predictedRNA?.arousal ?? -1
            if left != right { return left > right }
            return lhs.sentence < rhs.sentence
        }
        return ranked.enumerated().map { index, gene in
            placementRow(gene: gene, position: index, ranked: ranked)
        }
    }

    public func evaluate(sentence: String) -> LogicalHormoneTierRow? {
        tierList().first { $0.sentence == sentence }
    }

    public func hormones() -> [LogicalHormone] {
        let ranked = genes.values
            .filter(\.canEvaluatePlacement)
            .sorted { lhs, rhs in
                let left = lhs.predictedRNA?.arousal ?? -1
                let right = rhs.predictedRNA?.arousal ?? -1
                if left != right { return left > right }
                return lhs.sentence < rhs.sentence
            }
        var groups: [[LogicalHormoneDNA]] = []
        for gene in ranked {
            guard let last = groups.last,
                  let hormonePred = LogicalHormoneGenome.meanRNA(last.compactMap(\.predictedRNA)),
                  let predicted = gene.predictedRNA,
                  let observed = gene.observedRNA.last
            else {
                groups.append([gene])
                continue
            }
            let here = LogicalHormoneGenome.invertPredicted(
                predicted: predicted,
                observed: observed,
                history: gene.observedRNA,
                sequenceNumber: sequenceNumber,
                priorIntent: gene.sentence
            )
            let there = LogicalHormoneGenome.invertPredicted(
                predicted: hormonePred,
                observed: observed,
                history: gene.observedRNA,
                sequenceNumber: sequenceNumber,
                priorIntent: gene.sentence
            )
            if there.homeostaticDelta <= here.homeostaticDelta {
                groups[groups.count - 1].append(gene)
            } else {
                groups.append([gene])
            }
        }
        return groups.compactMap(formHormone)
    }

    public func hormone(sentence: String) -> LogicalHormone? {
        hormones().first { $0.memberSentences.contains(sentence) || $0.sentence == sentence }
    }

    private func formHormone(members: [LogicalHormoneDNA]) -> LogicalHormone? {
        let expressed = LogicalHormoneGenome.meanRNA(members.compactMap(\.predictedRNA))
        let lasts = members.compactMap { $0.observedRNA.last }
        let lastObserved = LogicalHormoneGenome.meanRNA(lasts)
        guard let expressed, let lastObserved, let lead = members.first else { return nil }
        let history = members.flatMap(\.observedRNA)
        let homeostasis = LogicalHormoneGenome.invertPredicted(
            predicted: expressed,
            observed: lastObserved,
            history: history,
            sequenceNumber: sequenceNumber,
            priorIntent: lead.sentence
        )
        return LogicalHormone(
            sentence: lead.sentence,
            memberSentences: members.map(\.sentence),
            expressed: expressed,
            lastObserved: lastObserved,
            homeostasis: homeostasis,
            observationCount: history.count
        )
    }

    private func placementRow(
        gene: LogicalHormoneDNA,
        position: Int,
        ranked: [LogicalHormoneDNA]
    ) -> LogicalHormoneTierRow {
        guard gene.canEvaluatePlacement,
              let predicted = gene.predictedRNA,
              let observed = gene.observedRNA.last
        else {
            return LogicalHormoneTierRow(
                sentence: gene.sentence,
                situation: gene.situation,
                effect: gene.effect,
                position: position,
                predicted: gene.predictedRNA,
                placementInvert: nil,
                neighborInvert: nil,
                belongsAtPosition: nil
            )
        }
        let here = LogicalHormoneGenome.invertPredicted(
            predicted: predicted,
            observed: observed,
            history: gene.observedRNA,
            sequenceNumber: sequenceNumber,
            priorIntent: gene.sentence
        )
        let neighborPreds = [position - 1, position + 1].compactMap { index -> InvertedAffectVector? in
            guard ranked.indices.contains(index) else { return nil }
            return ranked[index].predictedRNA
        }
        guard let neighborMean = LogicalHormoneGenome.meanRNA(neighborPreds) else {
            return LogicalHormoneTierRow(
                sentence: gene.sentence,
                situation: gene.situation,
                effect: gene.effect,
                position: position,
                predicted: predicted,
                placementInvert: here,
                neighborInvert: nil,
                belongsAtPosition: nil
            )
        }
        let there = LogicalHormoneGenome.invertPredicted(
            predicted: neighborMean,
            observed: observed,
            history: gene.observedRNA,
            sequenceNumber: sequenceNumber,
            priorIntent: gene.sentence
        )
        return LogicalHormoneTierRow(
            sentence: gene.sentence,
            situation: gene.situation,
            effect: gene.effect,
            position: position,
            predicted: predicted,
            placementInvert: here,
            neighborInvert: there,
            belongsAtPosition: here.homeostaticDelta <= there.homeostaticDelta
        )
    }
}
