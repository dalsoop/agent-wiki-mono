import Foundation

extension LedgerStore {
    /// ID 접두/일치 → 제목 정확 일치 → alias:* 태그 일치 → 제목 접두 일치 → 제목 부분일치 순으로 객체 검색.
    public func resolveCandidates(_ objects: [LedgerObject], query: String) -> [LedgerObject] {
        let q = query.precomposedStringWithCanonicalMapping.lowercased()

        // 1) ID 접두/일치 (모든 판 — head 제한 없음)
        let byID = objects.filter { $0.id.lowercased().hasPrefix(q) }
        if !byID.isEmpty { return byID }

        let headObjects = heads(objects)

        // 2) 제목 정확 일치 (head 만)
        let byExactTitle = headObjects.filter {
            $0.title?.precomposedStringWithCanonicalMapping.lowercased() == q
        }
        if !byExactTitle.isEmpty { return byExactTitle }

        // 3) alias:* 태그 일치 (head 만)
        let targetAlias = q.hasPrefix("alias:") ? q : "alias:" + q
        let byAlias = headObjects.filter { obj in
            obj.tags.contains {
                $0.precomposedStringWithCanonicalMapping.lowercased() == targetAlias
            }
        }
        if !byAlias.isEmpty { return byAlias }

        // 4) 제목 접두 일치 (head 만)
        let byTitlePrefix = headObjects.filter {
            $0.title?.precomposedStringWithCanonicalMapping.lowercased().hasPrefix(q) == true
        }
        if !byTitlePrefix.isEmpty { return byTitlePrefix }

        // 5) 제목 부분 일치 (head 만 fallback)
        let byTitleSubstring = headObjects.filter {
            $0.title?.precomposedStringWithCanonicalMapping.lowercased().contains(q) == true
        }
        if !byTitleSubstring.isEmpty { return byTitleSubstring }

        return []
    }
}
