import Foundation

/// 논문에서 정동 대조가 갈리는 호르몬 칸. 감정 이름이 아니다.
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

/// 한 호르몬의 상대 움직임. 크기가 아니라 올랐는지다.
public enum LogicalHormoneMotion: String, Sendable, Codable, Equatable {
    case rose
    case fell
    case held
}

/// 두 호르몬의 상대 관계.
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

/// 관측된 움직임만 담는다. 없는 칸은 만들지 않는다.
public struct LogicalHormonePattern: Sendable, Codable, Equatable {
    public let motions: [LogicalHormoneChannel: LogicalHormoneMotion]

    public init(_ motions: [LogicalHormoneChannel: LogicalHormoneMotion]) {
        self.motions = motions
    }

    public var isEmpty: Bool { motions.isEmpty }

    public var observedChannels: [LogicalHormoneChannel] {
        motions.keys.sorted()
    }

    public subscript(_ channel: LogicalHormoneChannel) -> LogicalHormoneMotion? {
        motions[channel]
    }

    public var pairContrasts: [LogicalHormonePairContrast] {
        let channels = observedChannels
        guard channels.count >= 2 else { return [] }
        var pairs: [LogicalHormonePairContrast] = []
        for i in 0..<(channels.count - 1) {
            for j in (i + 1)..<channels.count {
                let left = channels[i]
                let right = channels[j]
                guard let leftMotion = self[left], let rightMotion = self[right] else { continue }
                pairs.append(LogicalHormonePairContrast(
                    left: left,
                    right: right,
                    relation: Self.relation(leftMotion, rightMotion)
                ))
            }
        }
        return pairs
    }

    public var catecholamineRose: Bool {
        observedChannels.contains { $0.isCatecholamine && self[$0] == .rose }
    }

    public var catecholamineFellWithoutRise: Bool {
        let seen = observedChannels.filter(\.isCatecholamine)
        guard !seen.isEmpty else { return false }
        return seen.contains { self[$0] == .fell } && !catecholamineRose
    }

    public static func relation(
        _ left: LogicalHormoneMotion,
        _ right: LogicalHormoneMotion
    ) -> LogicalHormonePairRelation {
        if left == .held || right == .held {
            return .oneHeld
        }
        if left == right {
            return .sameDirection
        }
        return .opposed
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

/// 숫자 정동이 아니다. 상대 패턴이 정동이다.
public struct LogicalAffect: Sendable, Codable, Equatable {
    public let polarity: LogicalAffectPolarity?
    public let alert: LogicalAffectAlert?
    public let patternShifted: Bool?
    public let pairs: [LogicalHormonePairContrast]

    public init(
        polarity: LogicalAffectPolarity?,
        alert: LogicalAffectAlert?,
        patternShifted: Bool?,
        pairs: [LogicalHormonePairContrast]
    ) {
        self.polarity = polarity
        self.alert = alert
        self.patternShifted = patternShifted
        self.pairs = pairs
    }
}

/// 관측된 호르몬 움직임을 서로 대조해 논리 정동을 만든다.
public enum LogicalHormoneContrast {
    /// 한 칸이면 대조할 상대가 없다. 빠진 호르몬은 움직이지 않았다고 치지 않는다.
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

    /// Frankenhaeuser: 카테콜아민만 오르면 쾌·불쾌를 말하지 않는다. 코르티솔이 같이 오르거나 둘 다 내리면 불협화다.
    /// Heinrichs: 옥시토신이 오르고 코르티솔이 내리면 조화다.
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
