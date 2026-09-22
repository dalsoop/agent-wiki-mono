import Foundation

/// 카탈로그 순이 아니라 매칭된 공고를 먼저 받는다.
public enum HarvestQueue: Sendable {
    public static func nextIDs(
        catalogIDs: [String],
        visited: Set<String>,
        prefer: [String]
    ) -> [String] {
        let pending = catalogIDs.filter { $0.hasPrefix("PBLN_") && !visited.contains($0) }
        let pendingSet = Set(pending)
        var seen = Set<String>()
        var preferred: [String] = []
        for id in prefer where pendingSet.contains(id) && seen.insert(id).inserted {
            preferred.append(id)
        }
        let rest = pending.filter { !seen.contains($0) }
        return preferred + rest
    }

    public static func preferIDs(fromLastMatch data: Data, minScore: Int = 20) -> [String] {
        guard let root = FileLoad.jsonObject(from: data) as? [String: Any] else { return [] }
        let hits = root["hits"] as? [[String: Any]] ?? []
        return hits.compactMap { hit in
            let score = hit["score"] as? Int ?? 0
            guard score >= minScore else { return nil }
            let program = hit["program"] as? [String: Any]
            return program?["id"] as? String
        }.filter { $0.hasPrefix("PBLN_") }
    }
}
