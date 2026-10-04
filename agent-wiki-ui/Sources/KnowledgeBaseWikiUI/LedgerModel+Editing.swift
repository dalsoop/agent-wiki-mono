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
        guard loadedHeadID != nil else { return }
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
        guard let headID = loadedHeadID,
              let current = objects.first(where: { $0.id == headID }) else { return }
        let title = editorTitle.trimmingCharacters(in: .whitespaces)
        guard editorBody != current.body || title != (current.title ?? "") else { return }
        do {
            // 저장 = 개정. ledger 3 는 공포 경로, ledger 2 는 옛 발행(LedgerHumanEdit 한 자리).
            let revisionID = try performEdit(.amend(
                target: headID, title: title.isEmpty ? nil : title, body: editorBody, cites: current.cites))
            loadedHeadID = revisionID
            selectedDocumentID = revisionID
            refresh()
            errorMessage = nil
        } catch {
            errorMessage = "저장 실패: \(error)"
        }
    }

    func newDocument() {
        flushPendingSave()
        do {
            // ledger 3 는 빈 본문 공포를 거부하므로 자리 표시 본문으로 시작한다.
            let objectID = try performEdit(.create(title: nil, body: isLedgerThreeWorld ? "(새 기록)\n" : "", cites: []))
            refresh()
            select(documents.first { $0.id == objectID })
        } catch {
            errorMessage = "생성 실패: \(error)"
        }
    }

    /// 사용자에겐 "삭제" — 배관은 철회 발행. 기록은 남고 복구 가능.
    func delete(_ document: LedgerDocument) {
        flushPendingSave()
        do {
            _ = try performEdit(.repeal(target: document.head.id, reason: "deleted by user"))
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
            refresh()
            select(documents.first { $0.id == objectID } ?? documents.first { $0.id == document.head.id })
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
            refresh()
            select(documents.first { $0.id == revisionID })
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
            refresh()
            select(documents.first { $0.id == revisionID })
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
            refresh()
            select(documents.first { $0.id == revisionID })
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
