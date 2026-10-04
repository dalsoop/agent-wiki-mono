import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateMirrorKit
import StateRootKit
import SwiftUI

// 편집 — 저장=개정판 발행, 상태 미러
extension LedgerModel {
    // MARK: - 편집 (저장 = 개정판 발행, 배관은 숨김)

    func select(_ document: LedgerDocument?) {
        flushPendingSave()
        selectedDocumentID = document?.id
        editorTitle = document?.title ?? ""
        editorBody = document?.head.body ?? ""
        loadedHeadID = document?.head.id
    }

    func editorChanged() {
        // 보관된 원장(전신)은 쓰지 않는다 — 입력칸이 막혀도 자동 저장이 돌지 않게 여기서 한 번 더 막는다.
        guard loadedHeadID != nil, !isReadOnlyWorld else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveRevision()
        }
    }

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveRevision()
    }

    private func saveRevision() {
        guard let pending = pendingRevision() else { return }
        do {
            // 저장 = 개정. ledger 3 는 공포 경로, ledger 2 는 옛 발행(LedgerHumanEdit 한 자리).
            let revisionID = try performEdit(pending.action)
            recordSavedRevision(revisionID, from: pending)
            // 새 판은 배경 읽기가 반영한 뒤에 고른다. 그 전에 새 id 로 바꾸면 목록에 아직 없어 `selectedDocument` 가
            // nil 이 되고 편집기가 빈 화면으로 깜빡인다(초점 잃음). 옛 head 로 두면 반영 뒤 계보로 이어진다.
            refresh { [weak self] in
                guard let self, let document = self.selectedDocument,
                      document.versions.contains(where: { $0.id == revisionID }) else { return }
                self.selectedDocumentID = document.head.id
            }
            errorMessage = nil
        } catch {
            errorMessage = L(.lawRecordSaveFailed, "\(error)")
        }
    }

    /// 편집기에 남은 변경 — 마지막으로 읽었거나 공포한 판과 다르면 그 판의 개정 동작. 같거나 쓸 수 없으면 nil.
    func pendingRevision() -> PendingRevision? {
        guard !isReadOnlyWorld, let headID = loadedHeadID, let current = revisionBase(headID) else { return nil }
        let title = editorTitle.trimmingCharacters(in: .whitespaces)
        guard editorBody != current.body || title != (current.title ?? "") else { return nil }
        return PendingRevision(
            headID: headID, title: title.isEmpty ? nil : title, body: editorBody, cites: current.cites)
    }

    /// 공포한 판을 편집기의 기준으로 — 배경 읽기가 반영하기 전에도 다음 저장이 이 판과 비교한다.
    func recordSavedRevision(_ id: String, from pending: PendingRevision) {
        session.savedRevision = PendingRevision(headID: id, title: pending.title, body: pending.body, cites: pending.cites)
        if loadedHeadID == pending.headID { loadedHeadID = id }
    }

    /// 판 하나의 제목·본문·인용 — 읽은 목록에 없으면 방금 공포한 판(`session.savedRevision`).
    private func revisionBase(_ id: String) -> (title: String?, body: String, cites: [LedgerObject.Cite])? {
        if let object = objects.first(where: { $0.id == id }) { return (object.title, object.body, object.cites) }
        if let saved = session.savedRevision, saved.headID == id { return (saved.title, saved.body, saved.cites) }
        return nil
    }

    /// 화면 삭제의 폐지 이유(원장 기록 본문 — 화면 문구가 아니다).
    static let deletedByUserReason = "deleted by user"

    func newDocument() {
        flushPendingSave()
        do {
            // ledger 3 는 빈 본문 공포를 거부하므로 자리 표시 본문으로 시작한다.
            let objectID = try performEdit(.create(
                title: nil, body: isLedgerThreeWorld ? Self.newRecordPlaceholderBody : "", cites: []))
            refresh { [weak self] in self?.select(self?.documents.first { $0.id == objectID }) }
        } catch {
            errorMessage = L(.lawRecordCreateFailed, "\(error)")
        }
    }

    /// 사용자에겐 "삭제" — 배관은 철회 발행. 기록은 남고 복구 가능.
    func delete(_ document: LedgerDocument) {
        flushPendingSave()
        do {
            _ = try performEdit(.repeal(target: document.head.id, reason: Self.deletedByUserReason))
            if selectedDocumentID == document.id { select(nil) }
            refresh()
        } catch {
            errorMessage = "삭제 실패: \(error)"
        }
    }

    /// 삭제 복구 — 철회 발행을 철회할 수는 없으니 내용을 새 판으로 재발행.
    func restoreDeleted(_ document: LedgerDocument) {
        do {
            let objectID = try performEdit(.restore(target: document.head.id))
            showDeleted = false
            let headID = document.head.id
            refresh { [weak self] in
                guard let self else { return }
                select(documents.first { $0.id == objectID } ?? documents.first { $0.id == headID })
            }
        } catch {
            errorMessage = "복구 실패: \(error)"
        }
    }

    /// 내 기록에 근거 인용 부착 — 기존 인용 + 새 인용으로 개정판 발행.
    func attachCitation(to document: LedgerDocument, evidenceID: String, rel: String) {
        flushPendingSave()
        var cites = document.head.cites.filter { $0.id != evidenceID }
        cites.append(.init(id: evidenceID, rel: rel))
        do {
            let revisionID = try performEdit(.amend(
                target: document.head.id, title: document.head.title, body: document.head.body, cites: cites))
            refresh { [weak self] in self?.select(self?.documents.first { $0.id == revisionID }) }
        } catch {
            errorMessage = "인용 부착 실패: \(error)"
        }
    }

    func detachCitation(from document: LedgerDocument, evidenceID: String) {
        flushPendingSave()
        let cites = document.head.cites.filter { $0.id != evidenceID }
        do {
            let revisionID = try performEdit(.amend(
                target: document.head.id, title: document.head.title, body: document.head.body, cites: cites))
            refresh { [weak self] in self?.select(self?.documents.first { $0.id == revisionID }) }
        } catch {
            errorMessage = "인용 해제 실패: \(error)"
        }
    }

    /// 문서가 인용한 근거 카드 — 인용한 판이 개정됐으면 stale=true ("근거 갱신됨").
    struct CitationCard: Identifiable {
        let evidenceHead: LedgerObject
        let citedID: String
        let rel: String
        let stale: Bool
        var id: String { citedID }
    }

    func citationCards(of document: LedgerDocument) -> [CitationCard] {
        guard let store else { return [] }
        let superseded = Set(objects.compactMap(\.supersedes))
        return document.head.cites.compactMap { cite in
            guard let cited = objects.first(where: { $0.id == cite.id }) else { return nil }
            let head = store.lineage(objects, of: headID(of: cite.id)) .first ?? cited
            return CitationCard(
                evidenceHead: head, citedID: cite.id, rel: cite.rel,
                stale: superseded.contains(cite.id))
        }
    }

    /// 어떤 판 id 든 그 계보의 현재 head id.
    private func headID(of id: String) -> String {
        var current = id
        while let successor = objects.first(where: { $0.supersedes == current }) {
            current = successor.id
        }
        return current
    }

    /// 기록 패널에서 옛 판으로 복원 — 그 내용을 새 판으로 발행(역사는 그대로).
    func restore(version: LedgerObject, in document: LedgerDocument) {
        flushPendingSave()
        do {
            let revisionID = try performEdit(.amend(
                target: document.head.id, title: version.title, body: version.body, cites: version.cites))
            refresh { [weak self] in self?.select(self?.documents.first { $0.id == revisionID }) }
        } catch {
            errorMessage = "복원 실패: \(error)"
        }
    }

    func publishState() {
        maybeRecheckCLI()   // 전 과정에서 드리프트 감지(20초 스로틀)
        let installed = Self.installedCLIVersion()
        let fleetSnapshot = Self.fleetStateSnapshot()
        struct State: Encodable {
            let root: String?
            let area: String
            let selectedDocumentID: String?
            let documentCount: Int
            let objectCount: Int
            let integrityProblems: Int
            let cliStale: Bool
            let cliInstalledVersion: String?
            let cliExpectedVersion: String
            let currentWorld: String?
            let fleetWorldCount: Int
            let fleetIssueCount: Int
            let fleetWorlds: [String]
            let destination: String
            let repositorySummarySchemaVersion: String?
            let orchestrationAdapterSchemaVersion: String?
            let orchestrationCapsuleSchemaVersion: String?
            let currentRepository: String?
            let repoId: String?
            let normalizedRemote: String?
            let worktreePath: String?
            let sourceCommit: String?
            let taskOpenCount: Int?
            let taskCompletedCount: Int?
            let taskUnboundCount: Int?
            let taskAwaitingWorkerCount: Int?
            let taskExecutionFailedCount: Int?
            let taskStaleCount: Int?
            let taskAwaitingVerificationCount: Int?
            let taskVerifiedCount: Int?
            let taskWorkerDoneAwaitingCount: Int?
            let taskStates: [RepositoryTaskItem]?
            let provenanceIssueCount: Int?
            // gujo 전송로 — 뒤처짐이 안 보여서 syncthing 이 몇 주간 죽은 줄 몰랐다(2026-07-29).
            // 관측 채널이 없으면 같은 사고가 반복되므로 상태 미러에 상시 노출한다.
            let gujoIsRepository: Bool
            let gujoHead: String?
            let gujoAhead: Int
            let gujoBehind: Int
            let gujoDirty: Int
            let gujoLastSync: Date?
            let gujoBlobsLocal: Int
            /// 마지막 blob plan/pull 이 관측한 "원격에만 있는 blob 수" (관측 전 nil).
            let gujoBlobsMissing: Int?
            let gujoPeers: [String]
            let gujoNeedsAttention: Bool
        }
        let gujo = Self.gujoStateSnapshot()
        let state = State(
            root: rootURL?.path,
            area: String(describing: area),
            selectedDocumentID: selectedDocumentID,
            documentCount: documentsRaw.count,
            objectCount: objects.count,
            integrityProblems: integrityProblemCount,
            cliStale: cliStaleVersion != nil || (!installed.isEmpty && installed != LedgerVersion.current),
            cliInstalledVersion: installed.isEmpty ? cliStaleVersion : installed,
            cliExpectedVersion: LedgerVersion.current,
            currentWorld: currentWorldName,
            fleetWorldCount: fleetSnapshot.worldCount,
            fleetIssueCount: fleetSnapshot.issueCount,
            fleetWorlds: fleetSnapshot.worldNames,
            destination: destination.rawValue,
            repositorySummarySchemaVersion: repositorySummary?.schemaVersion,
            orchestrationAdapterSchemaVersion: repositorySummary?.stateMirror.orchestrationAdapterSchemaVersion,
            orchestrationCapsuleSchemaVersion: repositorySummary?.stateMirror.orchestrationCapsuleSchemaVersion,
            currentRepository: repositorySummary?.stateMirror.currentRepository,
            repoId: repositorySummary?.stateMirror.repoId,
            normalizedRemote: repositorySummary?.stateMirror.normalizedRemote,
            worktreePath: repositorySummary?.stateMirror.worktreePath,
            sourceCommit: repositorySummary?.stateMirror.sourceCommit,
            taskOpenCount: repositorySummary?.stateMirror.taskOpenCount,
            taskCompletedCount: repositorySummary?.stateMirror.taskCompletedCount,
            taskUnboundCount: repositorySummary?.stateMirror.taskUnboundCount,
            taskAwaitingWorkerCount: repositorySummary?.stateMirror.taskAwaitingWorkerCount,
            taskExecutionFailedCount: repositorySummary?.stateMirror.taskExecutionFailedCount,
            taskStaleCount: repositorySummary?.stateMirror.taskStaleCount,
            taskAwaitingVerificationCount: repositorySummary?.stateMirror.taskAwaitingVerificationCount,
            taskVerifiedCount: repositorySummary?.stateMirror.taskVerifiedCount,
            taskWorkerDoneAwaitingCount: repositorySummary?.stateMirror.taskWorkerDoneAwaitingCount,
            taskStates: repositorySummary?.stateMirror.taskStates,
            provenanceIssueCount: repositorySummary?.stateMirror.provenanceIssueCount,
            gujoIsRepository: gujo.isRepository,
            gujoHead: gujo.head,
            gujoAhead: gujo.ahead,
            gujoBehind: gujo.behind,
            gujoDirty: gujo.dirty,
            gujoLastSync: gujo.lastSync,
            gujoBlobsLocal: gujo.blobsLocal,
            gujoBlobsMissing: gujo.blobsMissing,
            gujoPeers: gujo.peers.map(\.name),
            gujoNeedsAttention: gujo.needsAttention
        )
        StateMirror.publish(app: "memo-citation-ledger", state)
        StateMirror.publish(app: "knowledge-base-wiki", state)
    }

    /// gujo world 의 전송로 상태. 네트워크는 건드리지 않는다(로컬 ref 비교만) —
    /// 상태 게시가 원격 지연에 물리면 GUI 가 멎는다.
    nonisolated static func gujoStateSnapshot() -> GujoSync.Status {
        let config = LedgerConfig.load()
        let path = config.effectiveWorlds.first { $0.name == "gujo-wiki" }?.rootPath
            ?? StateRootKit.path("gujo-wiki")
        return GujoSync(root: URL(fileURLWithPath: path)).status(probeRemote: false)
    }

    nonisolated private static func fleetStateSnapshot() -> (worldCount: Int, issueCount: Int, worldNames: [String]) {
        do {
            let reg = try FleetStore().load()
            let report = FleetDiagnostics.doctor(registry: reg)
            let names = reg.worlds.map(\.name).sorted()
            return (reg.worlds.count, report.issues.count, names)
        } catch {
            return (0, 0, [])
        }
    }
}
