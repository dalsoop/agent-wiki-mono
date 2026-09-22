import Foundation

/// 연합 hit 한 줄 — world 정체성 + 인식론 strength + 관제 rank score.
public struct FleetHit: Sendable, Equatable, Codable {
    public var world: String
    public var id: String
    public var title: String?
    public var author: String
    public var type: String?
    public var domain: String?
    public var kind: String?
    public var knowledge: String?
    public var lexicalScore: Int
    public var strength: Double
    public var score: Double
    public var snippet: String
    public var body: String? = nil
}

/// score = strength × worldWeight × domainWeight × typeBoost × lexicalNorm
public enum FleetRanker: Sendable {
    public static func typeBoost(_ type: String?) -> Double {
        switch type {
        case "concept", "entity": return 1.15
        case "evidence", "decision": return 1.0
        case "index": return 0.9
        case "task", "handoff", "done", "run": return 0.85
        default: return 1.0
        }
    }

    public static func worldWeight(
        world: String,
        profile: AgentProfile,
        fleetEntry: FleetWorldEntry?
    ) -> Double {
        if let w = profile.worlds[world] { return w }
        if let d = fleetEntry?.defaultWeight { return d }
        return 1.0
    }

    public static func domainWeight(domain: String?, profile: AgentProfile) -> Double {
        guard let domain, let w = profile.domains[domain] else { return 1.0 }
        return w
    }

    /// lexicalScore(Int) 를 0.2…1.0 으로 눌러 strength 가 지배하지 않게.
    public static func lexicalNorm(_ lexical: Int) -> Double {
        guard lexical > 0 else { return 0.2 }
        return min(1.0, 0.2 + Double(lexical) * 0.15)
    }

    public static func score(
        strength: Double,
        lexical: Int,
        world: String,
        type: String?,
        domain: String?,
        profile: AgentProfile,
        fleetEntry: FleetWorldEntry?
    ) -> Double {
        strength
            * worldWeight(world: world, profile: profile, fleetEntry: fleetEntry)
            * domainWeight(domain: domain, profile: profile)
            * typeBoost(type)
            * lexicalNorm(lexical)
    }

    public static func rank(_ hits: [FleetHit]) -> [FleetHit] {
        hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.lexicalScore != $1.lexicalScore { return $0.lexicalScore > $1.lexicalScore }
            return $0.id < $1.id
        }
    }
}
