import Foundation
import KnowledgeBaseWikiCore

// ledger 3 원장 화면의 모델 쪽 — 메뉴 판정·이동·표시 모델 반영·되돌리기·재개.
// 표시 모델은 엔진(`LawContentsScreen`·`LawRecordList`·`LawRecordDetail`·`LawCourtScreen`·`LawDreamScreen`·
// `LawCredibilityScreen`)이 배경에서 만들고(`LedgerBackgroundReader.lawScreens`), 여기서는 결과만 반영한다.
// 쓰기(되돌리기·재개)는 엔진 함수(`LawDreamBatchRestore`·`LawDreamScreen.resume`)만 부른다 — 쓰기 게이트·경로 판정은 엔진에 있다.
// 근거: docs/business-rules.md "# agent-law(ledger 3)", 결정 0007·0008.
extension LedgerModel {
    /// 옆 메뉴 — ledger 3 원장이면 목차·기록·심급·드리밍·모델 신빙성, 아니면 지금 메뉴.
    var sidebarDestinations: [RepositoryDestination] { RepositoryDestination.menu(for: law.kind) }

    /// 지금 연 원장이 보관된 원장(전신)이라 읽기 전용인가 — 편집 버튼을 숨긴다.
    var isReadOnlyWorld: Bool { law.kind?.isReadOnly ?? false }

    /// 원장 판정 반영 — 메뉴가 바뀌면 그 메뉴의 첫 화면으로.
    func applyLawKind(_ kind: LawLedgerScreenKind?) {
        guard law.kind != kind else { return }
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
    /// `id` 는 64자 id 또는 이 원장 안에서 하나로 정해지는 앞자리(목차의 8자리).
    func showLawRecord(id: String) {
        destination = .lawRecords
        law.selectedRecordID = id
        law.recordDetail = nil
        reloadLawScreens()
        publishState()
    }

    /// 기록 상세를 닫고 기록 목록으로.
    func closeLawRecord() {
        if law.isEditingRecord { finishLawRecordEdit() }
        law.selectedRecordID = nil
        law.recordDetail = nil
    }

    // MARK: - 편집(기존 화면 편집을 기록 상세에서 연다 — 사용자 결정 "편집은 남김")

    /// 지금 연 기록을 기존 편집기로 연다. 저장은 지금처럼 `performEdit(.amend)`(사람 작성자, 쓰기 게이트, git 커밋).
    func editLawRecord() {
        guard !isReadOnlyWorld, let id = law.recordDetail?.record.id,
              let document = documentsRaw.first(where: { $0.versions.contains { $0.id == id } }) else { return }
        select(document)
        law.isEditingRecord = true
    }

    /// 편집을 마친다 — 남은 저장을 공포하고 개정판(새 head)의 상세로 돌아간다.
    func finishLawRecordEdit() {
        flushPendingSave()
        law.isEditingRecord = false
        if let head = selectedDocument?.head.id, head != law.selectedRecordID {
            law.selectedRecordID = head
            law.recordDetail = nil
        }
        reloadLawScreens()
    }

    /// 새 기록 — 기존 `newDocument` 와 같은 공포(자리 표시 본문)를 하고 바로 편집기로 연다.
    func newLawRecord() {
        guard !isReadOnlyWorld else { return }
        flushPendingSave()
        do {
            let objectID = try performEdit(.create(title: nil, body: "(새 기록)\n", cites: []))
            refresh { [weak self] in
                guard let self else { return }
                self.select(self.documentsRaw.first { $0.id == objectID })
                self.destination = .lawRecords
                self.law.selectedRecordID = objectID
                self.law.recordDetail = nil
                self.law.isEditingRecord = true
                self.reloadLawScreens()
            }
        } catch {
            errorMessage = "생성 실패: \(error)"
        }
    }

    /// 지금 연 기록 삭제 — 기존 `delete` 와 같은 폐지 공포(기록은 남고 복구 가능).
    func repealLawRecord() {
        guard !isReadOnlyWorld, let id = law.recordDetail?.record.id,
              let document = documentsRaw.first(where: { $0.versions.contains { $0.id == id } }) else { return }
        delete(document)
        law.isEditingRecord = false
        law.selectedRecordID = nil
        law.recordDetail = nil
        reloadLawScreens()
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

    // MARK: - 쓰기(버튼은 다음 작업)

    /// 드리밍 묶음 되돌리기 — 그 드리밍이 바꾼 모든 원장에서 한꺼번에(전부 아니면 전무). 사람 작성자, 화면 = 일반 경로.
    /// 결과(원장별 기록 수 또는 거부 이유)는 `law.actionMessage` 에 둔다. 되돌리면 엔진 규칙으로 자동 드리밍이 정지한다.
    func revertDreamBatch(_ batch: String) {
        guard let target = editTarget, let file = target.file else { return }
        let actor = LedgerHumanEdit.humanActor(device: file.currentDevice)
        let catalog = target.catalog
        runLawAction {
            switch try LawDreamBatchRestore.restore(batch: batch, actor: actor, file: file, catalog: catalog) {
            case .restored(let ledgers):
                return (ledgers.map { "\($0.world): 되돌림 \($0.records.count)건" }.joined(separator: "\n"), false)
            case .refused(let reasons):
                return (reasons.joined(separator: "\n"), true)
            case .partial(let written, let failed, let untouched, let reason):
                // 검사 뒤 쓰기 중 실패 — 어느 원장까지 썼는지 원장별로 남긴다(다음 화면의 확인 창이 보인다).
                let lines = written.map { "\($0.world): 되돌림 \($0.records.count)건" }
                    + ["\(failed.world): 실패(그 전에 \(failed.records.count)건 씀) — \(reason)"]
                    + untouched.map { "\($0): 쓰지 않음" }
                return (lines.joined(separator: "\n"), true)
            }
        }
    }

    /// 자동 드리밍 재개 — 사람 작성자(`LedgerHumanEdit.humanActor`)로 `LawDreamService.resume`. 재개 기록은 지금 연 원장에.
    func resumeDreaming() {
        guard let target = editTarget, let file = target.file else { return }
        let catalog = target.catalog
        runLawAction {
            let stored = try LawDreamScreen.resume(file: file, catalog: catalog, target: target)
            return (stored.map { String($0.id.prefix(8)) } ?? "", false)
        }
    }

    /// 쓰기 하나를 배경에서 하고 결과를 반영한 뒤 화면을 다시 읽는다.
    private func runLawAction(_ action: @escaping @Sendable () throws -> (message: String, isError: Bool)) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: (message: String, isError: Bool)
            do {
                result = try action()
            } catch {
                result = ("\(error)", true)
            }
            await self?.finishLawAction(result)
        }
    }

    private func finishLawAction(_ result: (message: String, isError: Bool)) {
        law.actionMessage = result.message
        law.actionIsError = result.isError
        reloadLawScreens()
    }
}
