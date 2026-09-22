import AgentSurfaceKit
import Foundation

/// 첫 실행 온보딩용 상태 한 줄 (Agent Browser `OnboardStatus` 와 같은 형태).
public struct OnboardStatus: Sendable, Equatable {
    public let ok: Bool
    public let detail: String
    public let hint: String?

    public init(ok: Bool, detail: String, hint: String? = nil) {
        self.ok = ok
        self.detail = detail
        self.hint = hint
    }
}

/// CLI · agent-wiki 스킬 surface · dual-entry 진단 (표시·attach 액션용).
///
/// 설치 본체는 `app-build-manager ship knowledge-base-wiki-swift release` /
/// `agent-wiki skill-install` 이 담당. 여기 함수는 상태 읽기와 surface attach 만 한다.
public enum Onboarding {
    public static let welcomeCompletedKey = "agentWikiWelcomeCompleted"

    /// PATH / Helpers 에서 안전한 `agent-wiki` CLI 경로.
    public static func cliStatus() -> OnboardStatus {
        if let path = DualEntry.resolveCLIPath() {
            return OnboardStatus(ok: true, detail: path, hint: nil)
        }
        return OnboardStatus(
            ok: false,
            detail: "",
            hint: "설치: app-build-manager ship knowledge-base-wiki-swift release"
        )
    }

    /// multi-home agent-wiki 스킬 부착 상태 (`AgentSurface.status`).
    public static func skillStatus() -> OnboardStatus {
        let st = AgentSurface.status()
        if st.missing.isEmpty, !st.installed.isEmpty {
            let homes = st.presentHomes.isEmpty
                ? "\(st.installed.count) paths"
                : st.presentHomes.joined(separator: ", ")
            return OnboardStatus(ok: true, detail: "부착됨 · \(homes)", hint: nil)
        }
        if !st.installed.isEmpty, !st.missing.isEmpty {
            return OnboardStatus(
                ok: false,
                detail: "부분 \(st.installed.count) paths",
                hint: "누락: \(st.missing.joined(separator: ", ")) — 온보딩에서 부착 또는 agent-wiki skill-install"
            )
        }
        return OnboardStatus(
            ok: false,
            detail: "",
            hint: "스킬 미부착 — 아래에서 부착 또는 agent-wiki skill-install"
        )
    }

    /// dual-entry: GUI 가 CLI 로 위장하지 않고 안전 CLI 가 있는지.
    public static func dualEntryStatus() -> OnboardStatus {
        let d = DualEntry.diagnose()
        if d.ok, let path = d.path {
            let stamp = d.stamp.map { " · stamp \($0)" } ?? ""
            return OnboardStatus(ok: true, detail: "\(path)\(stamp)", hint: nil)
        }
        let issue = d.issues.first ?? "안전 CLI 없음"
        return OnboardStatus(
            ok: false,
            detail: d.path ?? "",
            hint: issue
        )
    }

    /// 앱 surface 스킬을 현재 홈들에 부착.
    @discardableResult
    public static func attachSkillSurface(seedBundle: Bundle = .main) throws -> AgentSurfaceRules.AttachResult {
        try AgentSurface.attach(seedBundle: seedBundle)
    }
}
