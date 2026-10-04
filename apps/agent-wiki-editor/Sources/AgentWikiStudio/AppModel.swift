import Foundation
import Observation
import LocalizationKit
import AgentWikiStudioCore
import KnowledgeBaseWikiCore
import AppKit
import StateRootKit
import CommandKit

/// Studio 자체 창 영역 (monlith studio 표면의 경량 진입점).
enum StudioArea: String, CaseIterable, Identifiable {
    case notes = "내 기록"
    case capture = "수집"
    case recent = "최근"
    case world = "world"
    case publish = "발행"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .notes: return "note.text"
        case .capture: return "tray.and.arrow.down"
        case .recent: return "clock.arrow.circlepath"
        case .world: return "globe"
        case .publish: return "square.and.pencil"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let loc = LocalizationManager(baseBundle: ResourceBundle.localization())
    private let service = AgentWikiStudioService()

    var status: String = ""
    var world: String = StudioWriteWorld.inferred()
    var worldCatalog: [WikiWorldListItem] = []
    var area: StudioArea = .notes
    var output: String = ""
    var busy = false
    var lastError: String = ""

    /// 간단 발행 폼 (CLI publish 래퍼)
    var publishTitle: String = ""
    var publishBody: String = ""

    func L(_ key: L10nKey) -> String { loc.string(key.rawValue) }

    func L(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: loc.string(key.rawValue), locale: .current, arguments: args)
    }

    func refresh() async {
        worldCatalog = service.worldCatalog()
        if !worldCatalog.contains(where: { $0.name == world }),
           let firstPerson = worldCatalog.first(where: { $0.layer == .localPerson }) {
            world = firstPerson.name
        }
        status = await service.status()
        StateMirrorAdoption.publish(status: status.isEmpty ? "ok" : status)
    }

    func loadRemoteStatus() async {
        busy = true
        defer { busy = false }
        lastError = ""
        output = await service.remoteSharedStatus()
        StateMirrorAdoption.publish(status: "ok")
    }

    @discardableResult
    func run(_ parts: [String]) async -> Int32 {
        busy = true
        defer { busy = false }
        var args = ["--world", world]
        args.append(contentsOf: parts)
        let r = await service.forward(args: args)
        let ok = r.exitCode == 0
        lastError = ok ? "" : (r.stderr.isEmpty ? "exit \(r.exitCode)" : r.stderr)
        if !r.stdout.isEmpty {
            output = r.stdout
        } else if !ok {
            output = lastError
        }
        if !r.stderr.isEmpty, ok {
            output += (output.isEmpty ? "" : "\n") + r.stderr
        }
        StateMirrorAdoption.publish(status: ok ? "ok" : "error")
        return r.exitCode
    }

    func loadNotes() async {
        _ = await run(["list"])
    }

    func loadRecent() async {
        _ = await run(["recent"])
    }

    func loadWorld() async {
        busy = true
        defer { busy = false }
        status = await service.status()
        output = status
        lastError = ""
        StateMirrorAdoption.publish(status: status.isEmpty ? "ok" : status)
    }

    func showCaptureHelp() {
        lastError = ""
        output = """
        # 수집 (capture)

        웹 원자료 → 수집함:

        ```
        agent-wiki-studio --world \(world) capture <url> --title "제목" <<'EOF'
        (발췌 본문)
        EOF
        ```

        원장 GUI 수집함: 「원장 GUI」 버튼 (studio 표면).
        """
    }

    func showPublishCLIHint() {
        let title = publishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.isEmpty ? "제목" : title
        lastError = ""
        output = """
        # 발행 CLI

        ```
        agent-wiki --world \(world) publish --title "\(t)" --type note <<'EOF'
        \(publishBody.isEmpty ? "(본문)" : publishBody)
        EOF
        ```

        또는 아래 「발행 실행」으로 stdin 본문 호출.
        full dual-entry 정본: Studio Helpers `agent-wiki` (PATH 심링크).
        """
    }

    /// title + body 로 publish 시도. `publish` 는 본문을 stdin 으로 받는 CLI 계약이라
    /// `AgentWikiStudioService.publish`(Process 직접 구동, stdin 파이프)를 그대로 쓴다.
    func publishNow() async {
        let title = publishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = publishBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            lastError = "제목이 비어 있습니다"
            return
        }
        guard !body.isEmpty else {
            lastError = "본문이 비어 있습니다"
            return
        }
        busy = true
        defer { busy = false }
        let r = await service.publish(world: world, title: title, body: body, type: "note")
        let ok = r.exitCode == 0
        output = ok ? r.stdout : (r.stderr.isEmpty ? r.stdout : r.stderr)
        lastError = ok ? "" : (r.stderr.isEmpty ? "exit \(r.exitCode)" : r.stderr)
        if ok {
            publishTitle = ""
            publishBody = ""
        }
        StateMirrorAdoption.publish(status: ok ? "ok" : "error")
    }

    func select(_ newArea: StudioArea) async {
        area = newArea
        switch newArea {
        case .notes:
            if output.isEmpty { await loadNotes() }
        case .capture:
            showCaptureHelp()
        case .recent:
            await loadRecent()
        case .world:
            await loadWorld()
            if WikiWorldPresentation.classify(name: world, rootPath: "") == .remoteShared
                || world == "gujo-wiki" {
                await loadRemoteStatus()
            }
        case .publish:
            showPublishCLIHint()
        }
    }

    func reloadCurrentArea() async {
        switch area {
        case .notes: await loadNotes()
        case .capture: showCaptureHelp()
        case .recent: await loadRecent()
        case .world: await loadWorld()
        case .publish: showPublishCLIHint()
        }
    }

    /// 원장 GUI 를 **studio 표면** 으로 연다 (수집·발행·에이전트 영역).
    @discardableResult
    func openLedgerGUI() -> Bool {
        writeSurface("studio")
        return openAgentWikiApp()
    }

    func openMonolithStudioSurface() { _ = openLedgerGUI() }

    /// surface=all — monlith 전체 영역 (이관 전 임시 디버그).
    @discardableResult
    func openFullSurface() -> Bool {
        writeSurface("all")
        return openAgentWikiApp()
    }

    private func writeSurface(_ value: String) {
        let dir = StateRootKit.url(".agent-wiki")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try value.write(to: dir.appendingPathComponent("surface"), atomically: true, encoding: .utf8)
        } catch {
            lastError = "surface 기록 실패: \(error.localizedDescription)"
        }
    }

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
        if safeResult.ok {
            lastError = ""
            return true
        } else {
            lastError = "원장 GUI 실행 실패: \(safeResult.stderr)"
            return false
        }
    }
}
