import Foundation
import KnowledgeBaseWikiCore

/// 메뉴 막대 동기화 표시 — `agent-law` 의 마지막 동기화 시각·커밋 대기 수·push 여부.
/// 값은 `LawGitSync.display()`(네트워크 없음) 하나에서 읽는다. 근거: docs/architecture.md "agent-law (ledger 3)".
public enum AgentLawSyncSummary {
    public static let worldName = "agent-law"

    /// 설정에 등록된 `agent-law` 원장 루트. 없으면 nil.
    public static func ledgerRoot(config: LedgerConfig = LedgerConfig.load()) -> URL? {
        config.effectiveWorlds.first { $0.name == worldName }.map { URL(fileURLWithPath: $0.rootPath) }
    }

    public static func text(_ display: LawSyncDisplay, now: Date = Date()) -> String {
        guard display.isRepository else { return "\(worldName) · git 저장소 아님" }
        let last: String
        if let date = display.lastSync {
            let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
            last = minutes < 1 ? "방금" : (minutes < 120 ? "\(minutes)분 전" : "\(minutes / 60)시간 전")
        } else {
            last = "없음"
        }
        let push: String
        switch display.pushed {
        case .some(true): push = "push ✓"
        case .some(false): push = "push ✗"
        case .none: push = "push —"
        }
        var line = "\(worldName) · 마지막 동기화 \(last) · 커밋 대기 \(display.pending) · \(push)"
        if let error = display.error, display.pushed != true { line += "\n\(error)" }
        return line
    }

    /// 현재 설정 기준 요약. 원장이 없으면 그 사실을 적는다.
    public static func current(config: LedgerConfig = LedgerConfig.load()) -> String {
        guard let root = ledgerRoot(config: config) else { return "\(worldName) · 원장 미등록" }
        return text(LawGitSync(ledgerRoot: root).display())
    }
}
