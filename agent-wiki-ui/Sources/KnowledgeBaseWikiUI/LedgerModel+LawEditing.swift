import Foundation
import KnowledgeBaseWikiCore

// 화면 편집의 쓰기 자리 — ledger 3 원장이면 공포 경로(`LedgerHumanEdit` → `LawEnactService`:
// 작성자 human·speaker user·기기 키·쓰기 게이트·후처리), ledger 2 원장이면 옛 발행. 결정 0007.
extension LedgerModel {
    /// 현재 world 의 쓰기 대상(호스트 설정 파일 하나에서 world 목록·기기 키를 읽는다).
    var editTarget: LawLedgerTarget? {
        guard let name = currentWorldName, let rootURL else { return nil }
        let config = LedgerConfig.load()
        let file = WorldBoundBootstrap.load(from: LedgerConfig.configURL, overlay: config)
        var catalog = WorldCatalogLoader.merging(file: file, config: config)
        if catalog.world(named: name) == nil {
            catalog.worlds.append(BoundWorld(name: name, rootPath: rootURL.path))
        }
        return LawLedgerTarget(
            worldName: name, root: rootURL, catalog: catalog,
            registeredDevices: file.devices ?? [], currentDevice: file.currentDevice)
    }

    var isLedgerThreeWorld: Bool { editTarget?.isLedgerThree ?? false }

    /// 편집 하나를 쓰고 새 기록 id 를 돌려준다.
    func performEdit(_ action: LedgerHumanEditAction) throws -> String {
        guard let target = editTarget else { throw LedgerHumanEditError.notFound(currentWorldName ?? "-") }
        return try LedgerHumanEdit.perform(action, target: target)
    }

    /// 묶음 되돌리기 — ledger 3 는 원상회복(공포 경로), ledger 2 는 옛 rollback.
    func performRestore(batch: String) throws {
        guard let target = editTarget else { return }
        if target.isLedgerThree {
            try LawEnactService.restore(
                batch: batch, actor: LedgerHumanEdit.humanActor(device: target.currentDevice), target: target)
            return
        }
        if let denial = target.writeDenial() { throw LedgerHumanEditError.writeDenied(denial) }
        _ = try LedgerStore(root: target.root).rollback(batchID: batch, author: LedgerHumanEdit.ledgerTwoAuthor)
    }

    /// ledger 2 전용 화면 쓰기(심사·수집·위키 절 편집 등). ledger 3 원장이나 보관된 원장이면 nil 과 안내.
    func legacyWritableStore() -> LedgerStore? {
        guard let store, let target = editTarget else { return nil }
        if target.isLedgerThree {
            errorMessage = "ledger 3 원장에서는 이 화면 기능을 쓸 수 없음 — agent-wiki enact 를 쓰세요"
            return nil
        }
        if let denial = target.writeDenial() {
            errorMessage = denial.message
            return nil
        }
        return store
    }

    /// ledger 3 원장의 기록을 화면 목록용 투영으로 읽는다(읽기 전용).
    func ledgerThreeObjects(root: URL) -> [LedgerObject] {
        LawLedgerProjection.objects(LawStore(root: root).scan())
    }
}
