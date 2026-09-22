import Foundation

/// 경험칙 주입 — 카르파시식 SPL(System Prompt Learning)의 '검색→프롬프트 주입' 스텝.
/// 회고 에이전트가 발행한 경험칙(retrospective)을, 실행하는 에이전트의 프롬프트에 되먹인다.
/// 이게 있어야 "학습"이 닫힌다 — 회고는 만들기만 하고 안 쓰면 write-only.
extension LedgerStore {
    /// 한 역할에 적용할 경험칙 head 들 — 최신순. 역할을 본문에 언급한 것 우선, 부족하면 일반 경험칙으로 채움.
    public func experienceRules(_ objects: [LedgerObject], forRole role: String, limit: Int = 5) -> [LedgerObject] {
        let all = heads(objects)
            .filter { $0.effectiveType == "retrospective" && $0.retracts == nil }
            .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
        let roleSpecific = all.filter { !role.isEmpty && $0.body.contains(role) }
        let general = all.filter { !roleSpecific.contains($0) }
        return Array((roleSpecific + general).prefix(limit))
    }

    /// 프롬프트에 붙일 경험칙 블록(없으면 빈 문자열). 제목 한 줄씩.
    public func experienceRulesPrompt(_ objects: [LedgerObject], forRole role: String, limit: Int = 5) -> String {
        let rules = experienceRules(objects, forRole: role, limit: limit)
        guard !rules.isEmpty else { return "" }
        var s = "\n\n## 지난 경험칙 (과거 실패에서 배운 것 — 반드시 반영하라)\n"
        for r in rules {
            let title = (r.title ?? "").replacingOccurrences(of: "회고: ", with: "")
            s += "- \(title)\n"
        }
        return s
    }
}
