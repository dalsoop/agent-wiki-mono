import Foundation
import WikiLedgerKit

// ledger 3 공포 경로 — CLI 명령과 화면 편집이 같은 경로를 쓴다.
// 순서: 쓰기 게이트(`WorldWriteGate`) → 범위 해석기를 넣은 `LawStore.enact` → 공포 후처리.
// 근거: docs/business-rules.md "공포·개정·폐지·원상회복", docs/standards.md "agent-law (ledger 3)", 결정 0007.

/// 공포 대상 원장과 그 판정에 필요한 설정.
public struct LawLedgerTarget: Sendable {
    public let worldName: String
    public let root: URL
    public let catalog: WorldBindingCatalog
    public let registeredDevices: [String]
    public let currentDevice: String?
    /// 호스트 설정(테넌트 대응표·R2 자리). 소환·증언 확인의 표준 원천이 쓴다.
    public let file: BoundLedgerFile?
    /// 소환·증언 확인의 원천을 바꿔 끼운다(시험). 비우면 `LawSummonSources.standard(file:)`.
    public var summonOverride: LawSummonSources?

    public init(
        worldName: String, root: URL, catalog: WorldBindingCatalog,
        registeredDevices: [String], currentDevice: String?, file: BoundLedgerFile? = nil,
        summonSources: LawSummonSources? = nil
    ) {
        self.worldName = worldName
        self.root = root
        self.catalog = catalog
        self.registeredDevices = registeredDevices
        self.currentDevice = currentDevice
        self.file = file
        self.summonOverride = summonSources
    }

    /// 설정 파일 하나에서. `catalog` 를 주지 않으면 파일의 world 목록.
    public init(worldName: String, file: BoundLedgerFile, catalog: WorldBindingCatalog? = nil) {
        let resolvedCatalog = catalog ?? WorldBindingCatalog(worlds: file.effectiveWorlds)
        let rootPath = resolvedCatalog.world(named: worldName)?.rootPath
            ?? file.effectiveWorlds.first { $0.name == worldName }?.rootPath ?? ""
        self.init(
            worldName: worldName, root: URL(fileURLWithPath: rootPath), catalog: resolvedCatalog,
            registeredDevices: file.devices ?? [], currentDevice: file.currentDevice, file: file)
    }

    public var store: LawStore { LawStore(root: root) }

    /// 소환·증언 확인이 세션을 찾는 원천.
    public var summonSources: LawSummonSources { summonOverride ?? .standard(file: file) }

    /// 공포 경로의 기본 증언 확인자(세션 대조). 부를 때만 세션·R2 를 읽는다.
    public var defaultTestimony: any LawTestimonyVerifying { LawSessionTestimony(target: self) }
    public var isLedgerThree: Bool { catalog.isLedgerThree(worldName) }

    /// 쓰기 허용 판정(보관된 원장·미등록 기기). 판정은 `WorldWriteGate` 한 곳.
    public func writeDenial() -> WorldWriteDenial? {
        WorldWriteGate.denial(
            targetWorld: worldName, catalog: catalog,
            registeredDevices: registeredDevices, currentDevice: currentDevice)
    }
}

public enum LawEnactServiceError: Error, CustomStringConvertible {
    case writeDenied(WorldWriteDenial)
    case reference(LawReferenceError)
    case actor(LawActorError)
    case enact(LawEnactError)
    case notLedgerThree(String)

    public var description: String {
        switch self {
        case .writeDenied(let denial): return denial.message
        case .reference(let error): return error.description
        case .actor(let error): return error.description
        case .enact(let error): return error.description
        case .notLedgerThree(let world): return "ledger 3 원장이 아님: \(world)"
        }
    }
}

public enum LawEnactService {
    /// 범위 해석기와 증언 확인자를 넣은 공포 문맥. 확인자를 주지 않으면 세션 대조 확인자(`LawSessionTestimony`,
    /// 표준 원천)가 기본이다. 공포·원상회복은 대상 원장의 설정으로 만든 확인자(`LawLedgerTarget.defaultTestimony`)를 넘긴다.
    public static func context(
        index: LawScopeIndex, testimony: (any LawTestimonyVerifying)? = nil
    ) -> LawEnactContext {
        let verifier = testimony ?? LawSessionTestimony(
            scope: LawSummonScope(world: index.current, catalog: index.catalog)) { .standard(file: nil) }
        return LawEnactContext(
            testimony: verifier, resolver: LawScopeReferenceResolver(index: index),
            promotions: LawPromotionWitness(index: index))
    }

    public static func scope(of target: LawLedgerTarget) -> LawScopeIndex {
        LawScopeIndex(current: target.worldName, catalog: target.catalog)
    }

    /// 참조 토큰들을 64자 id 로 푼다(범위 밖이면 인용 게이트 거부).
    public static func resolveReferences(_ tokens: [String], index: LawScopeIndex) throws -> [String] {
        do {
            return try tokens.map { try LawReferenceLookup.resolve($0, index: index) }
        } catch let error as LawReferenceError {
            throw LawEnactServiceError.reference(error)
        }
    }

    /// 공포. 쓰기 게이트를 먼저 보고, 범위 해석기로 `LawStore.enact` 를 부른 뒤 후처리 자리를 부른다.
    @discardableResult
    public static func enact(
        _ draft: LawDraft, target: LawLedgerTarget, index: LawScopeIndex? = nil,
        testimony: (any LawTestimonyVerifying)? = nil, now: Date = Date()
    ) throws -> LawStoredRecord {
        guard target.isLedgerThree else { throw LawEnactServiceError.notLedgerThree(target.worldName) }
        if let denial = target.writeDenial() { throw LawEnactServiceError.writeDenied(denial) }
        let scope = index ?? scope(of: target)
        do {
            let stored = try target.store.enact(
                draft, now: now, context: context(index: scope, testimony: testimony ?? target.defaultTestimony))
            LawEnactAftermath.run(target: target, enacted: [stored])
            return stored
        } catch let error as LawEnactError {
            throw LawEnactServiceError.enact(error)
        }
    }

    /// 원상회복 — 묶음의 기록마다 새 기록을 공포한다(같은 게이트·해석기·후처리).
    @discardableResult
    public static func restore(
        batch: String, actor: LawActor, target: LawLedgerTarget,
        testimony: (any LawTestimonyVerifying)? = nil, perRuling: String? = nil, now: Date = Date()
    ) throws -> [LawStoredRecord] {
        guard target.isLedgerThree else { throw LawEnactServiceError.notLedgerThree(target.worldName) }
        if let denial = target.writeDenial() { throw LawEnactServiceError.writeDenied(denial) }
        do {
            let enacted = try target.store.restore(
                batch: batch, actor: actor, now: now,
                context: context(index: scope(of: target), testimony: testimony ?? target.defaultTestimony),
                perRuling: perRuling)
            LawEnactAftermath.run(target: target, enacted: enacted)
            return enacted
        } catch let error as LawEnactError {
            throw LawEnactServiceError.enact(error)
        }
    }

    /// 체크포인트 — 지금 기록 집합의 수와 해시를 적고 이전 체크포인트를 `checkpoints` 로 인용한다.
    @discardableResult
    public static func checkpoint(
        actor: LawActor, target: LawLedgerTarget, now: Date = Date()
    ) throws -> LawStoredRecord {
        let records = target.store.scan()
        let ids = records.map(\.id).sorted()
        let previous = records.filter { $0.record.type == LawRecordType.checkpoint.rawValue }.last
        let draft = LawDraft(
            actor: actor, title: "체크포인트: 기록 \(ids.count)개", type: LawRecordType.checkpoint.rawValue,
            cites: previous.map { [LawCite(id: $0.id, rel: LawRelation.checkpoints.rawValue)] } ?? [],
            body: "records: \(ids.count)\nset-sha256: \(LawHash.sha256Hex(ids.joined(separator: "\n")))\n")
        return try enact(draft, target: target, now: now)
    }
}

/// 공포가 성공한 직후 부르는 후처리 자리. 모든 ledger 3 쓰기(공포·개정·폐지·원상회복·사실인정·체크포인트·승격·화면 편집)가 지난다.
/// 1) 그 기록 파일만 git 에 커밋(`LawGitCommit.commit`, 저장소 잠금 안). 잠금·커밋 실패는 공포 실패가 아니고 "커밋 대기"로 남아
///    다음 `sync`(`LawGitSync.sync`)가 커밋한다. git 저장소가 아닌 원장 루트는 건너뛴다.
/// 2) 파생 색인 갱신.
public enum LawEnactAftermath {
    @discardableResult
    public static func run(target: LawLedgerTarget, enacted: [LawStoredRecord]) -> LawGitCommitOutcome {
        guard !enacted.isEmpty else { return .committed(0) }
        // 커밋 대기는 저장소의 표시 파일(`agent-law-pending`)과 작업본 상태에 남고, 화면·`sync` 가 읽는다.
        let outcome = LawGitCommit.commit(enacted, ledgerRoot: target.root)
        refreshDerivedIndex(root: target.root)
        return outcome
    }

    /// 파생 색인(`state/index.db`)·그래프(`state/graph.db`)가 있으면 따라오게 한다. 캐시라 실패는 조용히 넘긴다.
    public static func refreshDerivedIndex(root: URL) {
        let indexPath = root.appendingPathComponent("state/index.db")
        guard FileManager.default.fileExists(atPath: indexPath.path) else { return }
        LedgerIndex(root: root).sync(objectsDir: root.appendingPathComponent("objects"))
        let graphPath = root.appendingPathComponent("state/graph.db")
        guard FileManager.default.fileExists(atPath: graphPath.path) else { return }
        let objects = LawLedgerProjection.objects(LawStore(root: root).scan())
        LedgerGraph(root: root).rebuild(objects: objects, events: [])
    }
}
