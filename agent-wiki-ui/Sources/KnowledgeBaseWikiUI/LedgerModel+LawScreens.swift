import Foundation
import KnowledgeBaseWikiCore

// ledger 3 원장 화면의 모델 쪽 — 메뉴 판정·이동·표시 모델 반영·되돌리기·재개.
// 표시 모델은 엔진(`LawContentsScreen`·`LawRecordList`·`LawRecordDetail`·`LawCourtScreen`·`LawDreamScreen`·
// `LawCredibilityScreen`)이 배경에서 만들고(`LedgerBackgroundReader.lawScreens`), 여기서는 결과만 반영한다.
// 쓰기(되돌리기·재개)는 엔진 함수(`LawDreamBatchRestore`·`LawDreamScreen.resume`)만 부른다 — 쓰기 게이트·경로 판정은 엔진에 있다.
// 기록 편집(새 기록·끝낼 때 저장·삭제)은 `LedgerHumanEdit.perform` 을 배경에서 부르고 결과만 메인에 반영한다.
// 근거: docs/business-rules.md "# agent-law(ledger 3)", 결정 0007·0008.
extension LedgerModel {
    /// 옆 메뉴 — ledger 3 원장이면 목차·기록·심급·드리밍·모델 신빙성, 아니면 지금 메뉴.
    var sidebarDestinations: [RepositoryDestination] { RepositoryDestination.menu(for: law.kind) }

    /// 지금 연 원장에 쓰지 않는가 — 보관된 원장(전신)이거나, 아직 판정 전(배경 읽기가 끝나기 전)이면 읽기 전용.
    /// 판정은 원장을 열 때마다 첫 배경 읽기(`applyRefresh` → `applyLawKind`)가 채운다(원장 폴더가 있으면 늘 채워진다).
    var isReadOnlyWorld: Bool { law.kind?.isReadOnly ?? true }

    /// 보관된 원장(전신)으로 판정됐는가 — "읽기 전용" 띠를 보인다(판정 전에는 띠를 보이지 않는다).
    var isArchivedWorld: Bool { law.kind?.isReadOnly == true }

    /// 원장 판정 반영 — 메뉴가 바뀌면 그 메뉴의 첫 화면으로.
    func applyLawKind(_ kind: LawLedgerScreenKind?) {
        guard law.kind != kind else { return }
        if law.isEditingRecord, kind?.usesLawScreens != true { finishLawRecordEdit(returnToRecord: false) }
        law.kind = kind
        let menu = RepositoryDestination.menu(for: kind)
        if !menu.contains(destination) { destination = menu.first ?? .overview }
    }

    /// 배경에서 만든 표시 모델 반영. 읽는 사이 거르기·기간·선택이 바뀌었으면 그 칸은 버리고 다시 읽는다.
    func applyLawScreens(_ screens: LawScreensSnapshot, for input: LedgerRefreshInput) {
        law.contents = screens.contents
        law.court = screens.court
        law.dream = screens.dream
        integrityProblemCount = screens.contents.summary.violations
        var stale = false
        if input.credibilityPeriod == law.credibilityPeriod { law.credibility = screens.credibility } else { stale = true }
        if input.recordFilter == law.recordFilter { law.records = screens.records } else { stale = true }
        if input.selectedRecordID == law.selectedRecordID { law.recordDetail = screens.recordDetail } else { stale = true }
        if input.selectedBatch == law.selectedBatch { law.batchChanges = screens.batchChanges } else { stale = true }
        if stale { reloadLawScreens() }
    }

    /// 객체 변경과 무관하게 표시 모델을 다시 읽는다(배경).
    func reloadLawScreens() {
        session.refresh.forceLawReload = true
        refresh()
    }

    // MARK: - 이동

    /// 기록 상세로 이동 — 모든 화면(목차 줄·기록 목록·심급·드리밍·신빙성)이 이 한 경로를 쓴다.
    /// `id` 는 64자 id 또는 이 원장 안에서 하나로 정해지는 앞자리(목차의 8자리). 이 원장에 없으면 배경 읽기가
    /// 드리밍 대상 원장·읽기 범위(상위·전신)에서 찾는다(`LawRecordDetail.load(id:target:records:otherLedgers:)`).
    func showLawRecord(id: String) {
        if law.isEditingRecord { finishLawRecordEdit(returnToRecord: false) }
        destination = .lawRecords
        law.selectedRecordID = id
        law.recordDetail = nil
        reloadLawScreens()
        publishState()
    }

    /// 기록 상세를 닫고 기록 목록으로.
    func closeLawRecord() {
        if law.isEditingRecord { finishLawRecordEdit(returnToRecord: false) }
        law.selectedRecordID = nil
        law.recordDetail = nil
    }

    // MARK: - 편집(기존 화면 편집을 기록 상세에서 연다 — 사용자 결정 "편집은 남김")

    /// 이 상세에서 편집·삭제를 보일까 — 지금 원장의 현행 판이고, 기록 목록이 다루는 유형(`LawRecordList.listedTypes`)일 때만.
    /// 다른 원장(드리밍 대상·상위·전신)의 기록은 그 원장을 열어 고친다.
    func canEditLawRecord(_ detail: LawRecordDetail) -> Bool {
        guard !isReadOnlyWorld, detail.world == currentWorldName, detail.isInForce else { return false }
        return LawRecordList.isListed(type: detail.record.record.type)
    }

    /// 지금 연 기록을 기존 편집기로 연다. 자동 저장은 지금처럼 `saveRevision`(사람 작성자, 쓰기 게이트, git 커밋).
    func editLawRecord() {
        guard !law.isWriting, let detail = law.recordDetail, canEditLawRecord(detail) else { return }
        guard let document = lawEditableDocument(containing: detail.record.id) else {
            errorMessage = L(.lawRecordNotEditable, LawRecordText.shortID(detail.record.id))
            return
        }
        law.isEditingRecord = true
        select(document)
    }

    /// 편집을 마친다 — 남은 변경을 배경에서 공포하고, `returnToRecord` 면 마지막으로 공포한 판(새 head)의 상세로 돌아간다.
    /// 다른 메뉴·다른 기록·다른 원장으로 떠날 때는 `returnToRecord: false`(저장만 하고 그 자리로 가지 않는다).
    func finishLawRecordEdit(returnToRecord: Bool = true) {
        saveTask?.cancel()
        saveTask = nil
        law.isEditingRecord = false
        let world = currentWorldName
        guard let pending = pendingRevision() else {
            let last = loadedHeadID
            clearLawEditor()
            if returnToRecord, let last { openEditedRecord(last) } else { reloadLawScreens() }
            return
        }
        // 편집기 내용은 공포가 끝날 때까지 둔다 — 실패하면 그대로 다시 연다.
        runLawEdit(pending.action, world: world, followUp: .saved(pending, returnToRecord: returnToRecord))
    }

    /// 새 기록 — 기존 `newDocument` 와 같은 공포(자리 표시 본문)를 하고 바로 편집기로 연다.
    func newLawRecord() {
        guard !isReadOnlyWorld, !law.isWriting else { return }
        if law.isEditingRecord { finishLawRecordEdit(returnToRecord: false) }
        runLawEdit(
            .create(title: nil, body: Self.newRecordPlaceholderBody, cites: []), world: currentWorldName, followUp: .created)
    }

    /// 지금 연 기록 삭제 — 기존 `delete` 와 같은 폐지 공포(기록은 남는다). 확인은 화면이 받는다.
    func repealLawRecord() {
        guard !law.isWriting, let detail = law.recordDetail, canEditLawRecord(detail) else { return }
        guard let document = lawEditableDocument(containing: detail.record.id) else {
            errorMessage = L(.lawRecordNotEditable, LawRecordText.shortID(detail.record.id))
            return
        }
        if law.isEditingRecord { finishLawRecordEdit(returnToRecord: false) }
        runLawEdit(
            .repeal(target: document.head.id, reason: LedgerModel.deletedByUserReason),
            world: currentWorldName, followUp: .repealed)
    }

    /// 새 기록의 자리 표시 본문 — ledger 3 는 빈 본문 공포를 거부한다. `newDocument` 와 같은 값.
    static var newRecordPlaceholderBody: String { L(.lawRecordNewPlaceholder) + "\n" }

    /// 편집 쓰기 뒤에 할 일.
    enum LawEditFollowUp: Sendable {
        case created
        case saved(PendingRevision, returnToRecord: Bool)
        case repealed
    }

    /// 편집 쓰기 하나를 배경에서 한다. 쓰기 대상(원장)은 부른 순간에 잡는다 — 그 사이 원장을 바꿔도 옛 원장에 쓴다.
    private func runLawEdit(_ action: LedgerHumanEditAction, world: String?, followUp: LawEditFollowUp) {
        guard let target = editTarget else {
            finishLawEdit(.failure(LedgerHumanEditError.notFound(world ?? "-")), world: world, followUp: followUp)
            return
        }
        law.isWriting = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try LedgerHumanEdit.perform(action, target: target) }
            await self?.finishLawEdit(result, world: world, followUp: followUp)
        }
    }

    private func finishLawEdit(_ result: Result<String, any Error>, world: String?, followUp: LawEditFollowUp) {
        law.isWriting = false
        let sameWorld = world == currentWorldName
        switch (result, followUp) {
        case (.success(let id), .created):
            guard sameWorld else { return }
            refresh { [weak self] in
                guard let self, self.currentWorldName == world else { return }
                self.destination = .lawRecords
                self.law.selectedRecordID = id
                self.law.recordDetail = nil
                self.law.isEditingRecord = true
                self.select(self.lawEditableDocument(containing: id))
                self.reloadLawScreens()
            }
        case (.success(let id), .saved(let pending, let returnToRecord)):
            recordSavedRevision(id, from: pending)
            if loadedHeadID == pending.headID || loadedHeadID == id { clearLawEditor() }
            if returnToRecord, sameWorld { openEditedRecord(id) } else { reloadLawScreens() }
        case (.success, .repealed):
            if sameWorld {
                law.selectedRecordID = nil
                law.recordDetail = nil
            }
            reloadLawScreens()
        case (.failure(let error), .created):
            errorMessage = L(.lawRecordCreateFailed, "\(error)")
        case (.failure(let error), .saved(_, let returnToRecord)):
            errorMessage = L(.lawRecordSaveFailed, "\(error)")
            // 남은 변경을 잃지 않게 편집기를 다시 연다(그 기록 화면에 머물러 있을 때만).
            if returnToRecord, sameWorld, destination == .lawRecords { law.isEditingRecord = true }
        case (.failure(let error), .repealed):
            errorMessage = L(.lawRecordRepealFailed, "\(error)")
        }
    }

    /// 편집한 기록(마지막으로 공포한 판)의 상세로 돌아간다.
    private func openEditedRecord(_ id: String) {
        if id != law.selectedRecordID {
            law.selectedRecordID = id
            law.recordDetail = nil
        }
        reloadLawScreens()
    }

    /// 편집기 선택을 비운다(저장하지 않는다 — 남은 변경은 부르는 쪽이 먼저 공포한다).
    private func clearLawEditor() {
        saveTask?.cancel()
        saveTask = nil
        selectedDocumentID = nil
        loadedHeadID = nil
        editorTitle = ""
        editorBody = ""
    }

    func setLawRecordFilter(_ filter: LawRecordListFilter) {
        guard law.recordFilter != filter else { return }
        law.recordFilter = filter
        reloadLawScreens()
    }

    func setCredibilityPeriod(_ period: LawCredibilityPeriod) {
        guard law.credibilityPeriod != period else { return }
        law.credibilityPeriod = period
        reloadLawScreens()
    }

    /// 드리밍 묶음 하나를 고르면 그 묶음이 바꾼 기록 목록을 읽는다.
    func selectDreamBatch(_ batch: String?) {
        law.selectedBatch = batch
        law.batchChanges = []
        reloadLawScreens()
    }

    // MARK: - 쓰기(되돌리기·재개)

    /// 드리밍 묶음 되돌리기 — 그 드리밍이 바꾼 모든 원장에서 한꺼번에(전부 아니면 전무). 사람 작성자, 화면 = 일반 경로.
    /// 결과(원장별 기록 수 또는 거부 이유)는 `law.actionMessage` 에 둔다. 되돌리면 엔진 규칙으로 자동 드리밍이 정지한다.
    func revertDreamBatch(_ batch: String) {
        guard !isReadOnlyWorld, let target = editTarget, let file = target.file else { return }
        let actor = LedgerHumanEdit.humanActor(device: file.currentDevice)
        let catalog = target.catalog
        runLawAction {
            switch try LawDreamBatchRestore.restore(batch: batch, actor: actor, file: file, catalog: catalog) {
            case .restored(let ledgers):
                return LawActionOutcome(
                    lines: ledgers.map { .reverted(world: $0.world, count: $0.records.count) }, isError: false)
            case .refused(let reasons):
                return LawActionOutcome(lines: reasons.map(LawActionLine.engine), isError: true)
            case .partial(let written, let failed, let untouched, let reason):
                // 검사 뒤 쓰기 중 실패 — 어느 원장까지 썼는지 원장별로 남긴다(다음 화면의 확인 창이 보인다).
                let lines: [LawActionLine] = written.map { .reverted(world: $0.world, count: $0.records.count) }
                    + [.failed(world: failed.world, written: failed.records.count, reason: reason)]
                    + untouched.map { .untouched(world: $0) }
                return LawActionOutcome(lines: lines, isError: true)
            }
        }
    }

    /// 자동 드리밍 재개 — 사람 작성자(`LedgerHumanEdit.humanActor`)로 `LawDreamService.resume`. 재개 기록은 지금 연 원장에.
    func resumeDreaming() {
        guard !isReadOnlyWorld, let target = editTarget, let file = target.file else { return }
        let catalog = target.catalog
        runLawAction {
            let stored = try LawDreamScreen.resume(file: file, catalog: catalog, target: target)
            return LawActionOutcome(lines: [stored.map { .resumed(id: $0.id) } ?? .notPaused], isError: false)
        }
    }

    /// 쓰기 하나를 배경에서 하고 결과를 반영한 뒤 화면을 다시 읽는다.
    private func runLawAction(_ action: @escaping @Sendable () throws -> LawActionOutcome) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: LawActionOutcome
            do {
                outcome = try action()
            } catch {
                outcome = LawActionOutcome(lines: [.engine("\(error)")], isError: true)
            }
            await self?.finishLawAction(outcome)
        }
    }

    private func finishLawAction(_ outcome: LawActionOutcome) {
        law.actionMessage = outcome.lines.map(\.text).joined(separator: "\n")
        law.actionIsError = outcome.isError
        reloadLawScreens()
    }
}

/// 되돌리기·재개 결과 한 줄 — 배경에서 값만 만들고 문구는 메인에서 번역 키로 짓는다(원장 이름·엔진 문자열은 인자).
enum LawActionLine: Sendable {
    case reverted(world: String, count: Int)
    case failed(world: String, written: Int, reason: String)
    case untouched(world: String)
    case resumed(id: String)
    case notPaused
    /// 엔진이 낸 거부 이유·오류 그대로.
    case engine(String)

    @MainActor var text: String {
        switch self {
        case .reverted(let world, let count): L(.LawDreamResultReverted, world, count)
        case .failed(let world, let written, let reason): L(.LawDreamResultFailed, world, written, reason)
        case .untouched(let world): L(.LawDreamResultUntouched, world)
        case .resumed(let id): L(.LawDreamResultResumed, LawRecordText.shortID(id))
        case .notPaused: L(.LawDreamResultNotPaused)
        case .engine(let message): message
        }
    }
}

struct LawActionOutcome: Sendable {
    let lines: [LawActionLine]
    let isError: Bool
}
