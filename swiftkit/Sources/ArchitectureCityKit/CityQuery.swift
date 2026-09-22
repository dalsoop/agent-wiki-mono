import Foundation

public struct CityQuery: Sendable, Equatable {
    public var usage: CityFilter
    public var text: String
    public var role: CityRole?
    public var district: String?

    public static let all = CityQuery()

    public init(usage: CityFilter = .all, text: String = "", role: CityRole? = nil, district: String? = nil) {
        self.usage = usage
        self.text = text
        self.role = role
        self.district = district
    }

    public func matches(_ item: CityItem, liveIds: Set<String> = []) -> Bool {
        switch usage {
        case .all: break
        case .used:
            if !(item.used || liveIds.contains(item.id)) { return false }
        case .unused:
            if item.used { return false }
        }
        if let role, item.role != role { return false }
        if let district, item.district != district { return false }
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return item.label.localizedCaseInsensitiveContains(needle)
            || item.district.localizedCaseInsensitiveContains(needle)
            || item.role.rawValue.localizedCaseInsensitiveContains(needle)
            || (item.file?.localizedCaseInsensitiveContains(needle) ?? false)
    }
}

public enum CityUsageWalk {
    public static func expand(seeds: Set<String>, outgoing: [String: [String]], rounds: Int = 8) -> Set<String> {
        var used = seeds
        var frontier = Array(seeds)
        var remaining = rounds
        while remaining > 0, !frontier.isEmpty {
            remaining -= 1
            var next: [String] = []
            for id in frontier {
                for dest in outgoing[id] ?? [] where used.insert(dest).inserted {
                    next.append(dest)
                }
            }
            frontier = next
        }
        return used
    }
}

public enum CityMention {
    public static func names(known: Set<String>, in text: String) -> Set<String> {
        let ordered = known.sorted { $0.count > $1.count }
        guard !ordered.isEmpty else { return [] }
        let pattern = ordered.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: "\\b(?:\(pattern))\\b") else { return [] }
        let ns = text as NSString
        var hit = Set<String>()
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            hit.insert(ns.substring(with: match.range))
        }
        return hit
    }
}

public enum CityRelations {
    public static func index(_ edges: [CityEdge]) -> (uses: [String: [String]], usedBy: [String: [String]]) {
        var uses: [String: [String]] = [:]
        var usedBy: [String: [String]] = [:]
        for edge in edges {
            if !(uses[edge.from] ?? []).contains(edge.to) {
                uses[edge.from, default: []].append(edge.to)
            }
            if !(usedBy[edge.to] ?? []).contains(edge.from) {
                usedBy[edge.to, default: []].append(edge.from)
            }
        }
        return (uses, usedBy)
    }
}
