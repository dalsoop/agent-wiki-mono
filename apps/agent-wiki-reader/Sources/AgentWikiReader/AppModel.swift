import Foundation
import Observation
import LocalizationKit
import AgentWikiReaderCore
import KnowledgeBaseWikiCore
import AppKit
import StateRootKit
import CommandKit

/// 읽기 전용 표면 영역. monlith LedgerAreaOwnership 의 reader 표면(wiki/changes/discuss/structure)
/// 중 이 앱이 자체 창에서 보여주는 부분집합.
enum ReaderArea: String, CaseIterable, Identifiable {
    case pages = "페이지"
    case graph = "그래프"
    case recent = "최근 변경"
    case discuss = "토론"
    case evidence = "증거"
    case events = "사건"
    case structure = "구조/상태"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pages: return "doc.text"
        case .graph: return "circle.hexagongrid"
        case .recent: return "clock.arrow.circlepath"
        case .discuss: return "bubble.left.and.bubble.right"
        case .evidence: return "paperclip"
        case .events: return "bolt.horizontal.circle"
        case .structure: return "square.stack.3d.up"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentWikiReaderService()

    var status: String = ""
    var world: String = WikiWorldPresentation.inferredPersonWorld()
    var worldCatalog: [WikiWorldListItem] = []
    var area: ReaderArea = .pages
    var busy = false
    var lastError: String = ""

    var pageQuery: String = ""
    var pageOutput: String = ""
    var graphQuery: String = ""
    var graphOutput: String = ""
    var recentOutput: String = ""
    var discussOutput: String = ""
    var evidenceQuery: String = ""
    var evidenceOutput: String = ""
    var eventsOutput: String = ""
    var structureOutput: String = ""

    /// 현재 선택된 영역의 출력 — 뷰가 바인딩하는 단일 지점.
    var currentOutput: String {
        switch area {
        case .pages: return pageOutput
        case .graph: return graphOutput
        case .recent: return recentOutput
        case .discuss: return discussOutput
        case .evidence: return evidenceOutput
        case .events: return eventsOutput
        case .structure: return structureOutput
        }
    }

    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        worldCatalog = service.worldCatalog(selected: world)
        if !worldCatalog.contains(where: { $0.name == world }),
           let firstPerson = worldCatalog.first(where: { $0.layer == .localPerson }) {
            world = firstPerson.name
        }
        status = await service.status()
        StateMirrorAdoption.publish(status: status.isEmpty ? "ok" : status)
    }

    func loadRemoteStatus() async {
        structureOutput = await service.remoteSharedStatus()
        area = .structure
    }

    private func run(_ parts: [String]) async -> String {
        busy = true
        defer { busy = false }
        var args = ["--world", world]
        args.append(contentsOf: parts)
        let r = await service.forward(args: args)
        let ok = r.exitCode == 0
        lastError = ok ? "" : (r.stderr.isEmpty ? "exit \(r.exitCode)" : r.stderr)
        StateMirrorAdoption.publish(status: ok ? "ok" : "error")
        return ok ? r.stdout : (r.stdout.isEmpty ? lastError : r.stdout)
    }

    func loadOnboarding() async {
        pageOutput = await run(["show", "e0d0f5f4"])
    }

    func loadList() async {
        pageOutput = await run(["list"])
    }

    func searchPages() async {
        let q = pageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { await loadList(); return }
        pageOutput = await run(["search", q])
    }

    func showPage(_ idOrTitle: String) async {
        let q = idOrTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        pageOutput = await run(["show", q])
    }

    func loadRecent() async {
        recentOutput = await run(["recent"])
    }

    func loadDiscuss() async {
        discussOutput = await run(["discuss"])
    }

    func loadStructure() async {
        structureOutput = await run(["structure"])
    }

    func loadGraphStatus() async {
        graphOutput = await run(["graph", "status"])
    }

    func showGraphNeighbors(_ id: String) async {
        let q = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { await loadGraphStatus(); return }
        graphOutput = await run(["graph", "neighbors", q])
    }

    func showGraphTimeline(_ id: String) async {
        let q = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { await loadGraphStatus(); return }
        graphOutput = await run(["graph", "timeline", q])
    }

    func loadEvidenceList() async {
        evidenceOutput = await run(["blob", "list"])
    }

    func showEvidence(_ sha: String) async {
        let q = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { await loadEvidenceList(); return }
        evidenceOutput = await run(["blob", "info", q])
    }

    func loadEvents() async {
        eventsOutput = await run(["event", "tail"])
    }

    /// 영역 전환 시 아직 안 불러온 영역만 채운다(탭 전환 매번 재요청하지 않음).
    func select(_ newArea: ReaderArea) async {
        area = newArea
        switch newArea {
        case .pages: if pageOutput.isEmpty { await loadOnboarding() }
        case .graph: if graphOutput.isEmpty { await loadGraphStatus() }
        case .recent: if recentOutput.isEmpty { await loadRecent() }
        case .discuss: if discussOutput.isEmpty { await loadDiscuss() }
        case .evidence: if evidenceOutput.isEmpty { await loadEvidenceList() }
        case .events: if eventsOutput.isEmpty { await loadEvents() }
        case .structure: if structureOutput.isEmpty { await loadStructure() }
        }
    }

    /// 현재 영역을 강제로 새로 불러온다.
    func reloadCurrentArea() async {
        switch area {
        case .pages: await loadList()
        case .graph: await loadGraphStatus()
        case .recent: await loadRecent()
        case .discuss: await loadDiscuss()
        case .evidence: await loadEvidenceList()
        case .events: await loadEvents()
        case .structure: await loadStructure()
        }
    }

    /// 원장 GUI(monlith) 를 **보고 표면(reader)** 으로 연다.
    /// `~/.agent-wiki/surface` = reader → monlith 가 허용 영역·창 제목을 맞춤.
    /// LedgerView 본 이관 전까지 monlith 가 Reader 제품의 실 GUI 호스트다.
    @discardableResult
    func openLedgerGUI() -> Bool {
        writeSurface(Self.surfaceValue)
        return openAgentWikiApp()
    }

    /// 하위 호환 별칭
    func openMonolithReaderSurface() { _ = openLedgerGUI() }

    private static let surfaceDirectory = ".agent-wiki"
    private static let surfaceFileName = "surface"
    private static let surfaceValue = "reader"

    private func writeSurface(_ value: String) {
        let dir = StateRootKit.url(Self.surfaceDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try value.write(
                to: dir.appendingPathComponent(Self.surfaceFileName),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            lastError = L(.AppModelString, error.localizedDescription)
        }
    }

    /// `/Applications/Agent Wiki.app` 또는 번들 이름으로 open. 없으면 lastError.
    private func openAgentWikiApp() -> Bool {
        let candidates = [
            "/Applications/Agent Wiki.app",
            "/Applications/AgentWiki.app",
            "/Applications/KnowledgeBaseWiki.app",
        ]
        guard candidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            lastError = "Agent Wiki.app 없음 — app-build-manager ship knowledge-base-wiki-swift"
            return false
        }
        let safeResult = SafeProcessRunner.run(
            "/usr/bin/open",
            ["-a", "Agent Wiki"]
        )
            lastError = ""
            return true
        } catch {
            lastError = L(.AppModelString_2, error.localizedDescription)
            return false
        }
    }
}

