import Foundation
import StateRootKit

/// monlith → Reader / Studio 이관 시 영역 소유권.
/// 1) env `AGENT_WIKI_SURFACE=reader|studio|all`
/// 2) else file `~/.agent-wiki/surface` (한 줄)
/// 3) default `all`
enum LedgerAreaOwnership: String {
    case reader
    case studio
    case both

    static func ownership(of area: LedgerArea) -> LedgerAreaOwnership {
        switch area {
        case .wiki, .graph, .changes, .discuss, .evidence, .events, .structure:
            return .reader
        case .myNotes, .triage, .review, .agents, .settings, .trash, .learning, .activity:
            return .studio
        }
    }

    static func resolvedSurface(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let e = env["AGENT_WIKI_SURFACE"], !e.isEmpty { return e.lowercased() }
        let url = StateRootKit.url(".agent-wiki/surface")
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return "all"
    }

    /// Reader/Studio 런처가 monlith 표면에 쓰는 파일.
    static func writeSurfaceFile(_ surface: String) throws {
        let dir = StateRootKit.url(".agent-wiki")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try surface.write(
            to: dir.appendingPathComponent("surface"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func allowedAreas(surface: String? = nil) -> Set<LedgerArea> {
        let s = (surface ?? resolvedSurface()).lowercased()
        let all: [LedgerArea] = [
            .myNotes, .evidence, .activity, .graph, .events, .changes, .discuss,
            .learning, .triage, .review, .agents, .wiki, .trash, .structure, .settings,
        ]
        switch s {
        case "reader", "report":
            return Set(all.filter { ownership(of: $0) == .reader || ownership(of: $0) == .both })
        case "studio", "ops":
            return Set(all.filter { ownership(of: $0) == .studio || ownership(of: $0) == .both })
        default:
            return Set(all)
        }
    }

    /// surface 별 기본 진입 영역 (허용 집합이 비지 않을 때).
    static func preferredArea(surface: String? = nil) -> LedgerArea {
        switch (surface ?? resolvedSurface()).lowercased() {
        case "reader", "report":
            return .wiki
        case "studio", "ops":
            return .myNotes
        default:
            return .myNotes
        }
    }

    /// 현재 영역이 surface 에 없으면 preferred 로 클램프. 이미 허용이면 유지.
    static func clampArea(_ current: LedgerArea, surface: String? = nil) -> LedgerArea {
        let allowed = allowedAreas(surface: surface)
        if allowed.contains(current) { return current }
        let preferred = preferredArea(surface: surface)
        if allowed.contains(preferred) { return preferred }
        return allowed.first ?? current
    }

    /// 창 제목 — Reader/Studio 런처가 surface 파일을 쓰면 monlith 창 이름도 맞춘다.
    static func windowTitle(surface: String? = nil) -> String {
        switch (surface ?? resolvedSurface()).lowercased() {
        case "reader", "report":
            return "Agent Wiki Reader"
        case "studio", "ops":
            return "Agent Wiki Studio"
        default:
            return "Agent Wiki"
        }
    }
}
