import Foundation
import Testing
import KnowledgeBaseWikiCore
import WikiLedgerKit
@testable import WikiCLIShared

/// 최종 검토의 명령 표면 시험 — 옛 예약 틱의 ledger 3 대응, 드리밍 끝 동기화의 가림 로컬 삭제, capabilities.
/// 근거: docs/operations.md "정기 작업과 동기화", docs/security.md "R2 와 세션", docs/contracts.md "agent-law 명령".
/// 임시 디렉터리만 쓴다(실제 LaunchAgent·원장·R2 를 건드리지 않는다).
@Suite struct ReviewFixesSurfaceTests {

    @Test func scheduleTicksUseLedgerThreeCommands() {
        let roles = scheduleTicks.map(\.role)
        #expect(roles == ["checkpoint", "verifier", "law-sync", "law-archive", "law-dream"])
        #expect(!scheduleTicks.contains { $0.arguments.contains("tick") })
        for role in retiredScheduleRoles { #expect(!roles.contains(role)) }
        #expect(scheduleTicks.first { $0.role == "checkpoint" }?.arguments == ["--as", "app:agent-wiki", "checkpoint"])
        #expect(scheduleTicks.first { $0.role == "verifier" }?.arguments == ["audit"])
        // 기본 원장(ledger 3)에서 64 로 막히는 옛 쓰기 명령이 없어야 한다.
        for tick in scheduleTicks {
            var arguments = tick.arguments
            if arguments.first == "--as" { arguments.removeFirst(2) }
            #expect(CommandSurfaceRouting.ledgerTwoOnlyGuidance(arguments, isLedgerThree: true) == nil, "\(tick.role)")
            #expect(CommandSurfaceRouting.retiredGuidance(arguments) == nil, "\(tick.role)")
        }
    }

    @Test func judgmentAmendIsALedgerWrite() {
        #expect(CommandSurfaceRouting.isLedgerWrite(["judgment", "amend", "abcd1234"]))
        #expect(!CommandSurfaceRouting.isLedgerWrite(["judgment", "show", "abcd1234"]))
    }

    @Test func capabilitiesListWorldStorageAndContentsJSON() {
        let support = capabilityJSONSupport
        #expect(support["world storage"] != nil)
        #expect(support["contents"] == true)
    }

    @Test func dreamFinishSyncAppliesRedactionLocalDeletions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-fixes-finish-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent("law")
        let file = BoundLedgerFile(
            worlds: [BoundWorld(name: "agent-law", rootPath: root.path, key: "law")],
            currentWorld: "agent-law", devices: ["mac"], currentDevice: "mac")
        let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
        let store = LawStore(root: root)
        let redacted = try store.putExhibit(Data("가린 증거물".utf8))
        let kept = try store.putExhibit(Data("남길 증거물".utf8))
        let actor = LawActor(author: "user:yun", kind: .human, device: "mac", runtime: "human")
        _ = try LawEnactService.enact(LawDraft(
            actor: actor, title: "가림", type: "redaction", exhibits: [redacted],
            body: "target: \(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: redacted))\nreason: r\n"),
            target: LawLedgerTarget(worldName: "agent-law", file: file, catalog: catalog), path: .redact)

        let messages = dreamFinishSync(file: file, catalog: catalog, objectStore: nil)
        #expect(!FileManager.default.fileExists(atPath: store.exhibitURL(sha256: redacted).path))
        #expect(FileManager.default.fileExists(atPath: store.exhibitURL(sha256: kept).path))
        #expect(messages.contains { $0.contains("가림 기록에 따른 로컬 삭제") })
        #expect(messages.contains { $0.contains("R2 없음") })
    }
}
