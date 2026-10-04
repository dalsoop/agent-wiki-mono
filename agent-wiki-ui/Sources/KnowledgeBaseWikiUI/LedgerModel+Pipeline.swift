import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateMirrorKit
import SwiftUI

// 파이프라인 가시화 — 단계·활동·에이전트·러너
extension LedgerModel {
    // MARK: - 파이프라인 가시화

    /// 객체의 파이프라인 단계 — UI 배지 공통 어휘.
    enum PipelineStage: String {
        case collected = "수집"      // 외부 origin(URL)에서 들어옴
        case bridged = "발행"        // 작업면(memo-vault)에서 확정되어 넘어옴
        case verified = "검증"       // supports/contradicts 스탬프
        case revised = "개정"
        case authored = "작성"       // 사람이 직접

        var color: String {
            switch self {
            case .collected: return "orange"
            case .bridged: return "blue"
            case .verified: return "green"
            case .revised: return "gray"
            case .authored: return "purple"
            }
        }
    }

    func stage(of object: LedgerObject) -> PipelineStage {
        if object.cites.contains(where: {
            EvidenceStrength.supportRels.contains($0.rel) || EvidenceStrength.contradictRels.contains($0.rel)
        }) { return .verified }
        if let origin = object.origin {
            if origin.hasPrefix("memo-vault:") { return .bridged }
            return .collected
        }
        if object.supersedes != nil { return .revised }
        return .authored
    }

    /// 파이프라인 단계별 건수 — 대시보드 흐름 스트립.
    var pipelineCounts: [(stage: PipelineStage, count: Int)] {
        let stages: [PipelineStage] = [.collected, .bridged, .verified]
        let all = objects.map { stage(of: $0) }
        return stages.map { stage in (stage, all.filter { $0 == stage }.count) }
    }

    /// 저장소 담당 에이전트 명단 — 엔진 중립 `.agents/roles/*.md` frontmatter.
    struct AgentRole: Identifiable {
        let name: String
        let descriptionText: String
        let lastActiveAt: Date?
        /// 실행 엔진 — 역할 frontmatter engine: (claude | codex | grok | opencode)
        var engine: String = "claude"
        /// 편성 — scheduled(상시) | on-demand(요청 시) | marker(기록용 표식) | ghost(정의 없음)
        var mode: String = "on-demand"
        var id: String { name }
    }

    var agentRoster: [AgentRole] {
        guard let roleStore = repositoryAgentRoleStore else { return [] }
        return roleStore.list().map { role in
            let lastActive = objects.filter { $0.author == role.id }.map(\.published).max()
            return AgentRole(
                name: role.id,
                descriptionText: role.summary.isEmpty ? role.displayName : role.summary,
                lastActiveAt: lastActive,
                engine: role.engine,
                mode: role.mode)
        }
        .sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
    }

    /// 명단 = 정의된 역할 ∪ 실제 발행 저자. 정의 없는 저자는 "유령"으로 경고 표시 —
    /// 프론트(정의 파일)와 백엔드(원장 저자)가 어긋나면 화면에 드러난다.
    var fullRoster: [AgentRole] {
        var roster = agentRoster
        let defined = Set(roster.map(\.name))
        let systemAuthors: Set<String> = ["human", "agent", "publish-test"]
        let ghosts = Set(objects.map(\.author)).subtracting(defined).subtracting(systemAuthors)
        for name in ghosts.sorted() {
            let lastActive = objects.filter { $0.author == name }.map(\.published).max()
            roster.append(AgentRole(
                name: name,
                descriptionText: "⚠ 저장소 역할 정의 없음 — .agents/roles/<kebab-id>.md를 연결해야 합니다",
                lastActiveAt: lastActive, mode: "ghost"))
        }
        return roster.sorted { ($0.lastActiveAt ?? .distantPast) > ($1.lastActiveAt ?? .distantPast) }
    }

    /// 백그라운드 러너 상태 — .runs/status.json (러너 규약: 진행 중 갱신, 끝나면 삭제).
    struct RunnerStatus: Decodable {
        let label: String
        let detail: String
        let updatedAt: String
    }

    /// 살아있는 러너 하트비트 전부 (.runs/status/*.json + 구 단일 파일 호환).
    var runnerStatuses: [RunnerStatus] {
        guard let root = rootURL else { return [] }
        var urls: [URL] = []
        let dir = root.appendingPathComponent(".runs/status")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) {
            urls += entries.filter { $0.pathExtension == "json" }
        }
        urls.append(root.appendingPathComponent(".runs/status.json"))
        let formatter = ISO8601DateFormatter()
        return urls.compactMap { url -> RunnerStatus? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let status: RunnerStatus
            do {
                status = try JSONDecoder().decode(RunnerStatus.self, from: data)
            } catch {
                return nil
            }
            // 10분 이상 갱신 없으면 죽은 러너로 간주
            if let at = formatter.date(from: String(status.updatedAt.prefix(19)) + "Z"),
               Date().timeIntervalSince(at) > 600 { return nil }
            return status
        }
    }

    var runnerStatus: RunnerStatus? { runnerStatuses.first }

    /// 분류 진행 — 이주 문서 중 분류 스탬프가 붙은 비율 (원장에서 파생, 5초 주기 갱신).
    var classificationProgress: (done: Int, total: Int)? {
        let imports = objects.filter { $0.author == "llmwiki-import" }
        guard !imports.isEmpty else { return nil }
        let importIDs = Set(imports.map(\.id))
        var screened = Set<String>()
        for object in objects {
            for cite in object.cites where cite.rel == Self.screenRel && importIDs.contains(cite.id) {
                screened.insert(cite.id)
            }
        }
        let done = screened.count
        return done < importIDs.count ? (done, importIDs.count) : nil  // 완료되면 표시 제거
    }


    func hasPublications(_ author: String) -> Bool {
        objects.contains { $0.author == author }
    }

    func lastPublished(by author: String) -> Date? {
        objects.filter { $0.author == author }.map(\.published).max()
    }

    /// 최근 10분 내 발행 = 지금 일하는 중.
    func isRecentlyActive(_ author: String) -> Bool {
        guard let last = lastPublished(by: author) else { return false }
        return Date().timeIntervalSince(last) < 600
    }

    /// 에이전트 연합 간선 — A 가 B 의 발행물을 인용한 실측 횟수.
    struct AgentEdge: Identifiable {
        let from: String
        let to: String
        let count: Int
        var id: String { from + "->" + to }
    }

    func agentEdges() -> [AgentEdge] { cachedAgentEdges }

    func publicationCount(of author: String) -> Int {
        objects.count { $0.author == author }
    }

    func recentPublications(limit: Int) -> [LedgerObject] {
        objects.sorted { ($0.published, $0.id) > ($1.published, $1.id) }.prefix(limit).map { $0 }
    }

    /// 에이전트별 발행 이력 (최신순).
    func publications(by author: String, limit: Int = 60) -> [LedgerObject] {
        objects.filter { $0.author == author }.sorted { ($0.published, $0.id) > ($1.published, $1.id) }.prefix(limit).map { $0 }
    }

    /// 워크벤치 지표 — 상단 스트립용.
    var reviewNeededCount: Int {
        evidenceDocuments.filter { $0.strength.freshness < 0.5 }.count
    }

    var contradictedCount: Int {
        evidenceDocuments.filter { $0.strength.contradictCount > 0 }.count
    }

    func strength(of document: LedgerDocument) -> EvidenceStrength? {
        store?.strength(objects, of: document.head)
    }

    /// 모든 문서 — 계보의 head 로 대표. 철회된 문서는 showDeleted 일 때만.
    var allDocuments: [LedgerDocument] { documentsRaw }

    /// 현재 영역의 문서 목록 (선택·역링크 공용).
    var documents: [LedgerDocument] {
        switch area {
        // 구조는 문서 축이 아니라 저장층 축이다 — 선택할 문서가 없다.
        case .structure: return []
        case .myNotes: return myDocuments
        case .evidence: return evidenceDocuments.map(\.document)
        case .agents: return documentsRaw
        case .wiki: return wikiDocuments + playbookDocuments
        case .triage: return triageQueue.map(\.document)
        case .review: return digestDocuments
        case .activity, .graph, .events, .changes, .discuss, .learning: return documentsRaw
        case .trash: return retractedDocuments.map(\.document)
        case .settings: return []
        }
    }

    var documentsRaw: [LedgerDocument] {
        var result: [LedgerDocument] = baseDocuments
            .filter { $0.isDeleted == showDeleted }.map(\.document)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            // 인덱스 있으면 FTS 로 매칭 id 만(전 본문 훑기 회피), 없으면 substring 폴백.
            if let index = searchIndex {
                let ids = Set(index.searchAllIDs(query, limit: 500))
                result = result.filter { ids.contains($0.head.id) }
            } else {
                let lower = query.lowercased()
                result = result.filter {
                    $0.title.lowercased().contains(lower) || $0.head.body.lowercased().contains(lower)
                }
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedDocument: LedgerDocument? {
        (documentsRaw + retractedDocuments.map(\.document)).first { $0.id == selectedDocumentID }
            ?? selectedDocumentID.flatMap { id in
                // 방금 개정으로 head id 가 바뀐 경우 계보로 추적.
                documentsRaw.first { $0.versions.contains { $0.id == id } }
                    // ledger 3 원장의 기록 편집 — 옛 화면의 검색어·삭제 보기로 걸러지지 않은 목록에서 찾는다.
                    ?? (law.isEditingRecord ? lawEditableDocument(containing: id) : nil)
            }
    }

    /// 삭제되지 않은 문서 중 이 판(`id`)을 계보에 가진 것 — 거르지 않은 목록(`baseDocuments`)에서.
    func lawEditableDocument(containing id: String) -> LedgerDocument? {
        baseDocuments.first { !$0.isDeleted && $0.document.versions.contains { $0.id == id } }?.document
    }

    /// 이 문서를 참조(인용)한 다른 문서들.
    func references(to document: LedgerDocument) -> [LedgerDocument] {
        let lineageIDs = Set(document.versions.map(\.id))
        return documentsRaw.filter { other in
            other.id != document.id
                && other.versions.contains { $0.cites.contains { lineageIDs.contains($0.id) } }
        }
    }

}

extension LedgerModel {
    var repositoryAgentRoleStore: RepositoryAgentRoleStore? {
        rootURL.map {
            RepositoryAgentRoleStore(
                repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: $0))
        }
    }

    /// 역할 정의 파일 경로 (`<repo>/.agents/roles/<name>.md`).
    func roleDefinitionPath(_ name: String) -> String? {
        guard let roleStore = repositoryAgentRoleStore else { return nil }
        return try? roleStore.load(id: name).fileURL.path
    }

    func roleDefinitionText(_ name: String) -> String? {
        roleDefinitionPath(name).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }

    /// 원장에 발행된 역할 정의 계보 (최신 head 우선).
    func roleDefinitionHistory(_ name: String) -> [LedgerObject] {
        objects.filter { $0.effectiveType == "role-definition" && $0.title == "역할정의: \(name)" }
            .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    }

    /// 엔진 변경 — frontmatter engine: 한 줄 교체 (정의 개정으로 기록).
    func setEngine(_ name: String, engine: String) {
        guard let text = roleDefinitionText(name) else { return }
        let old = fullRoster.first { $0.name == name }?.engine ?? "claude"
        guard old != engine else { return }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let index = lines.firstIndex(where: { $0.hasPrefix("engine:") }) {
            lines[index] = "engine: \(engine)"
        } else if let close = lines.dropFirst().firstIndex(of: "---") {
            lines.insert("engine: \(engine)", at: close)
        }
        saveRoleDefinition(name, text: lines.joined(separator: "\n"),
                           reason: "엔진 변경: \(old) → \(engine)")
    }

    /// 정의 저장 — 파일 갱신 + 원장 개정판 발행(supersedes 사슬 = 버전관리).
    func saveRoleDefinition(_ name: String, text: String, reason: String) {
        guard let roleStore = repositoryAgentRoleStore, let store = legacyWritableStore() else { return }
        do {
            let role = try roleStore.save(id: name, definition: text)
            let previousHead = store.heads(roleDefinitionHistory(name)).first
                ?? roleDefinitionHistory(name).first
            let body = "개정 사유: \(reason)\n\n" + text
            _ = try store.publish(
                author: "human", title: "역할정의: \(name)", type: "role-definition",
                body: body,
                supersedes: previousHead?.id,
                origin: "file://" + role.fileURL.path)
            refresh()
        } catch {
            errorMessage = "정의 저장 실패: \(error)"
        }
    }

    func createRepositoryAgentRole(
        id: String,
        displayName: String,
        summary: String,
        engine: String,
        responsibilities: String
    ) -> Bool {
        guard let roleStore = repositoryAgentRoleStore else { return false }
        do {
            let definition = try roleStore.makeDefinition(
                id: id,
                displayName: displayName,
                summary: summary,
                engine: engine,
                responsibilities: responsibilities)
            saveRoleDefinition(id, text: definition, reason: "저장소 담당 역할 생성")
            selectedAgentName = id
            return roleDefinitionPath(id) != nil
        } catch {
            errorMessage = "역할 생성 실패: \(error)"
            return false
        }
    }
}

extension LedgerModel {
    /// 주의 지표 — "지금 사람/에이전트 처리를 기다리는 것"만. 누적 총량은 소음이라 계기판에 안 올린다.
    struct AttentionItem: Identifiable {
        let label: String
        let count: Int
        let area: LedgerArea
        var id: String { label }
    }

    var attentionItems: [AttentionItem] {
        var items: [AttentionItem] = []
        let triage = triageQueue.count
        if triage > 0 { items.append(.init(label: "수집함 대기", count: triage, area: .triage)) }
        let review = digestDocuments.count
        if review > 0 { items.append(.init(label: "심사 대기", count: review, area: .review)) }
        // 미응답 토론 — 이의/질문/수정요청 중 아무도 cite 하지 않은 것
        let discussionTypes = ["objection", "question", "edit-request"]
        let citedIDs = Set(objects.flatMap { $0.cites.map(\.id) })
        let unanswered = objects.filter {
            discussionTypes.contains($0.effectiveType ?? "") && !citedIDs.contains($0.id)
        }.count
        if unanswered > 0 { items.append(.init(label: "미응답 토론", count: unanswered, area: .wiki)) }
        // 중단 의심 — reaper 가 아직 안 닫은 좌초 run
        let suspect = activityBatches.filter { batch in
            guard let run = runInfo(batch: batch) else { return false }
            return run.abandoned
        }.count
        if suspect > 0 { items.append(.init(label: "중단 의심", count: suspect, area: .activity)) }
        return items
    }
}
