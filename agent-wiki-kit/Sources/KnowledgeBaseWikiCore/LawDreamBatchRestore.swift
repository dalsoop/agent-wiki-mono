import Foundation
import WikiLedgerKit

// 드리밍 묶음 되돌리기(여러 원장 한꺼번에) — 드리밍 묶음 하나를 그 드리밍이 바꾼 모든 원장에서 원상회복한다.
// 전부 아니면 전무: 먼저 모든 대상 원장에서 원상회복 기록을 만들어 쓰기 게이트·경로 판정(`LawEnactPath.admit`, 기록별 경로는
// `LawRestorePaths`)·공포 검증을 모두 거치고(`LawStore.planRestore`), 하나라도 거부되면 어느 원장에도 쓰지 않는다.
// 원장별 규칙(되살린 판은 원래 화자 유지, 드리밍 묶음 경로)은 `LawStore.restore` 그대로이고, 부른 경로는 화면 = 일반 경로다.
// 되돌린 뒤의 자동 드리밍 정지는 엔진 규칙(`LawDreamPause` — 원상회복 기록에서 계산)이 맡는다.
// 근거: docs/business-rules.md "공포·개정·폐지·원상회복"(원상회복은 전부 아니면 전무, 드리밍 묶음은 반드시 되돌릴 수 있다),
// "드리밍"(드리밍 묶음이 원상회복되면 자동 드리밍 정지), 사용자 결정(2026-10-04) "모든 원장을 한꺼번에".

/// 한 원장에서 쓴 원상회복 기록.
public struct LawBatchRestoreLedger: Sendable {
    public let world: String
    public let records: [LawStoredRecord]
}

public enum LawDreamBatchRestoreOutcome: Sendable {
    /// 원장별로 쓴 원상회복 기록(모든 원장이 같은 새 묶음 id 를 공유한다).
    case restored([LawBatchRestoreLedger])
    /// 아무 원장에도 쓰지 않았다 — 거부 이유 목록(`<원장> <기록 8자>: <이유>`).
    case refused([String])
}

public enum LawDreamBatchRestore {
    /// - Parameter targets: 살펴볼 원장들(보통 `LawDreamService.targets`). 그중 묶음 기록이 있는 원장만 되돌린다.
    /// - Parameter testimony: 증언 확인자(시험). 비우면 원장마다 `LawLedgerTarget.defaultTestimony`.
    /// 검사 뒤 쓰는 도중 실패하면(경합) 쓴 기록은 지우지 않고 후처리한 뒤 `LawEnactServiceError.enact` 를 던진다.
    public static func restore(
        batch: String, actor: LawActor, targets: [LawLedgerTarget], now: Date = Date(),
        testimony: (any LawTestimonyVerifying)? = nil
    ) throws -> LawDreamBatchRestoreOutcome {
        let scanned = targets.map { (target: $0, records: $0.store.scan()) }
        let involved = scanned.filter { $0.records.contains { $0.record.batch == batch } }
        guard !involved.isEmpty else { return .refused([LawEnactError.batchNotFound(batch).description]) }
        let dreamBatches = scanned.reduce(into: Set<String>()) { $0.formUnion(LawDreamMarks(records: $1.records).dreamBatches) }
        guard dreamBatches.contains(batch) else {
            return .refused(["드리밍 묶음이 아님(드리밍 보고가 적은 묶음이 아님): \(batch) — 일반 묶음은 restore 로 원장마다"])
        }

        var refusals: [String] = []
        for entry in involved {
            if !entry.target.isLedgerThree {
                refusals.append(LawEnactServiceError.notLedgerThree(entry.target.worldName).description)
            } else if let denial = entry.target.writeDenial() {
                refusals.append("\(entry.target.worldName): \(denial.message)")
            }
        }
        guard refusals.isEmpty else { return .refused(refusals) }

        // 검사 — 아무것도 쓰지 않는다.
        let restoreBatch = LedgerID.generate(now: now)
        var plans: [(target: LawLedgerTarget, plan: LawStore.RestorePlan)] = []
        for entry in involved {
            let target = entry.target
            let scope = LawEnactService.scope(of: target)
            do {
                let plan = try target.store.planRestore(
                    batch: batch, actor: actor, now: now,
                    context: LawEnactService.context(index: scope, testimony: testimony ?? target.defaultTestimony),
                    path: .general, lookup: { scope.object(id: $0)?.law }, restoreBatch: restoreBatch)
                plans.append((target, plan))
            } catch LawEnactError.restoreRefused(let reasons) {
                refusals += reasons.map { "\(target.worldName) \($0)" }
            } catch let error as LawEnactError {
                refusals.append("\(target.worldName): \(error.description)")
            }
        }
        guard refusals.isEmpty else { return .refused(refusals) }

        // 쓰기 — 모든 원장의 검사가 통과한 뒤에만.
        var written: [LawBatchRestoreLedger] = []
        for (target, plan) in plans {
            do {
                let records = try target.store.applyRestore(plan)
                LawEnactAftermath.run(target: target, enacted: records)
                written.append(LawBatchRestoreLedger(world: target.worldName, records: records))
            } catch let error as LawEnactError {
                if case .restorePartiallyApplied(let applied, _, _) = error {
                    LawEnactAftermath.run(target: target, enacted: applied)
                }
                throw LawEnactServiceError.enact(error)
            }
        }
        return .restored(written)
    }

    /// 드리밍 원장 전부(`LawDreamService.targets`)를 살펴 되돌린다.
    public static func restore(
        batch: String, actor: LawActor, file: BoundLedgerFile, catalog: WorldBindingCatalog, now: Date = Date()
    ) throws -> LawDreamBatchRestoreOutcome {
        try restore(batch: batch, actor: actor, targets: LawDreamService.targets(file: file, catalog: catalog), now: now)
    }
}
