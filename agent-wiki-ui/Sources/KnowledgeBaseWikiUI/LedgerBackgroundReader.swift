import Foundation
import KnowledgeBaseWikiCore

// 화면 갱신의 읽기 — 설정 파일·원장 폴더·fleet 진단·git 살피기를 메인 스레드 밖에서 한다.
// 메인은 결과(`LedgerRefreshSnapshot`·`LedgerRepositorySnapshot`)만 반영한다.
// 2026-10-04 시작 멈춤 사고: 메인 스레드의 원장 폴더 훑기가 파일 접근 허용 창에 막혀 앱 전체가 멈췄다.
// 원장 종류(ledger 3 여부·보관 여부)는 설정으로 판정한다(`LawLedgerScreenKind`) — 폴더가 git 저장소인지로 판정하지 않는다.

/// 배경 읽기에 넘기는 메인 상태의 사본.
struct LedgerRefreshInput: Sendable {
    let openedRepositoryPath: String?
    let rootURL: URL?
    let currentWorldName: String?
    let worlds: [LedgerWorld]
    let objectIDs: [String]
    let scanCache: LedgerStore.ScanCache
    /// 마지막으로 읽은 ledger 3 원장 `objects/` 의 변화 표지(같으면 다시 읽지 않는다).
    let lawFingerprint: LawObjectsFingerprint?
    /// 객체가 바뀌지 않았어도 ledger 3 화면 표시 모델을 다시 읽는다(필터·기간·선택 변경).
    let forceLawReload: Bool
    /// 메인에 ledger 3 화면 표시 모델이 이미 있는가(없으면 객체 변경과 무관하게 읽는다).
    let lawLoaded: Bool
    let recordFilter: LawRecordListFilter
    let credibilityPeriod: LawCredibilityPeriod
    let selectedRecordID: String?
    let selectedBatch: String?
}

/// ledger 3 화면 표시 모델 한 벌(엔진이 만든 것).
struct LawScreensSnapshot: Sendable {
    let contents: LawContentsScreen
    let court: LawCourtScreen
    let dream: LawDreamScreen
    let credibility: LawCredibilityScreen
    let records: [LawRecordListRow]
    let recordDetail: LawRecordDetail?
    let batchChanges: [LawBatchChange]
}

/// 배경 읽기 결과.
struct LedgerRefreshSnapshot: Sendable {
    let input: LedgerRefreshInput
    let worlds: [LedgerWorld]
    let selectedWorldName: String?
    let rootURL: URL?
    /// 연 원장 폴더가 바뀌었다(선택·캐시를 비운다).
    let rootChanged: Bool
    let kind: LawLedgerScreenKind?
    /// 바뀐 객체 목록. nil 이면 바뀌지 않았다.
    let objects: [LedgerObject]?
    let scanCache: LedgerStore.ScanCache
    /// 마지막으로 읽은 ledger 3 원장 `objects/` 의 변화 표지(같으면 다시 읽지 않는다).
    let lawFingerprint: LawObjectsFingerprint?
    /// 다시 읽은 ledger 3 화면 표시 모델. nil 이면 그대로 둔다.
    let law: LawScreensSnapshot?
}

/// 저장소 개요·world 고르기 표시(배경에서 만든 것).
struct LedgerRepositorySnapshot: Sendable {
    let pickerItems: [WorldPickerItem]
    let identity: RepositoryIdentity?
    let summary: RepositorySummaryContract?
}

enum LedgerBackgroundReader {
    /// 현재 world 의 쓰기·판정 대상(호스트 설정 파일 하나에서 world 목록·기기 키를 읽는다).
    static func lawTarget(worldName: String, root: URL, config: LedgerConfig) -> LawLedgerTarget {
        let file = WorldBoundBootstrap.load(from: LedgerConfig.configURL, overlay: config)
        var catalog = WorldCatalogLoader.merging(file: file, config: config)
        if catalog.world(named: worldName) == nil {
            catalog.worlds.append(BoundWorld(name: worldName, rootPath: root.path))
        }
        return LawLedgerTarget(
            worldName: worldName, root: root, catalog: catalog,
            registeredDevices: file.devices ?? [], currentDevice: file.currentDevice, file: file)
    }

    /// 호스트 설정의 world 목록(층·원장 키·전신).
    static func catalog(config: LedgerConfig) -> WorldBindingCatalog {
        WorldCatalogLoader.merging(file: WorldBoundBootstrap.load(from: LedgerConfig.configURL, overlay: config), config: config)
    }

    static func read(_ input: LedgerRefreshInput) -> LedgerRefreshSnapshot {
        // CLI `world use` 로 밖에서 세계관이 바뀌면 앱도 따라간다(설정 파일이 정본).
        let config = LedgerConfig.load()
        let executionWorld = input.openedRepositoryPath.flatMap {
            RepositoryContext.resolve(cwd: $0, config: config)
        }?.world
        let selectedWorld = executionWorld ?? config.current
        let worlds = LedgerModel.mergedWorlds(config.effectiveWorlds, executionWorld: executionWorld)
        let root = selectedWorld.map { URL(fileURLWithPath: $0.rootPath) }
        let rootChanged = root != input.rootURL
        let worldChanged = rootChanged || worlds != input.worlds || selectedWorld?.name != input.currentWorldName

        guard let root, let name = selectedWorld?.name else {
            return LedgerRefreshSnapshot(
                input: input, worlds: worlds, selectedWorldName: selectedWorld?.name, rootURL: root,
                rootChanged: rootChanged, kind: nil, objects: input.objectIDs.isEmpty ? nil : [],
                scanCache: LedgerStore.ScanCache(), lawFingerprint: nil, law: nil)
        }
        let target = lawTarget(worldName: name, root: root, config: config)
        let kind = LawLedgerScreenKind(worldName: name, catalog: target.catalog)

        guard kind.isLedgerThree else {
            var cache = rootChanged ? LedgerStore.ScanCache() : input.scanCache
            let result = LedgerStore(root: root).scan(cache: &cache)
            return LedgerRefreshSnapshot(
                input: input, worlds: worlds, selectedWorldName: name, rootURL: root, rootChanged: rootChanged,
                kind: kind, objects: result.changed || input.objectIDs.isEmpty || worldChanged ? result.objects : nil,
                scanCache: cache, lawFingerprint: nil, law: nil)
        }

        // ledger 3 원장 — `objects/` 가 그대로면(파일 수·크기·최신 수정 시각) 다시 읽지 않는다.
        let fingerprint = target.store.objectsFingerprint()
        let unchanged = fingerprint == input.lawFingerprint && !worldChanged && !input.forceLawReload && input.lawLoaded
        guard !unchanged else {
            return LedgerRefreshSnapshot(
                input: input, worlds: worlds, selectedWorldName: name, rootURL: root, rootChanged: rootChanged,
                kind: kind, objects: nil, scanCache: input.scanCache, lawFingerprint: fingerprint, law: nil)
        }
        // 기록을 한 번 읽어 목록 투영과 화면 표시 모델 모두에 넘긴다(결정 0007: 읽기 전용 투영으로 같은 목록 자리에 싣는다).
        let records = target.store.scan()
        let projected = LawLedgerProjection.objects(records)
        return LedgerRefreshSnapshot(
            input: input, worlds: worlds, selectedWorldName: name, rootURL: root, rootChanged: rootChanged,
            kind: kind, objects: projected.map(\.id) != input.objectIDs || worldChanged ? projected : nil,
            scanCache: input.scanCache, lawFingerprint: fingerprint,
            law: lawScreens(target: target, records: records, input: rootChanged ? nil : input))
    }

    /// ledger 3 화면 표시 모델 한 벌 — 이 원장의 기록(`records`)은 한 번 읽은 것을 모든 화면이 같이 쓰고,
    /// 드리밍 원장들의 기록도 한 번만 읽어 목차(정지 판정)와 드리밍 화면이 같이 쓴다.
    /// `input` 이 nil 이면(원장이 바뀜) 기본 필터·기간·선택 없음으로 만든다.
    static func lawScreens(
        target: LawLedgerTarget, records: [LawStoredRecord], input: LedgerRefreshInput?, now: Date = Date()
    ) -> LawScreensSnapshot {
        let file = target.file ?? BoundLedgerFile(worlds: target.catalog.worlds)
        let dreamTargets = LawDreamService.targets(file: file, catalog: target.catalog)
        let dreamLedgers = dreamTargets.map {
            (world: $0.worldName, records: $0.worldName == target.worldName ? records : $0.store.scan())
        }
        let selected = input?.selectedRecordID
        let batch = input?.selectedBatch
        return LawScreensSnapshot(
            contents: LawContentsScreen.load(target: target, records: records, dreamLedgers: dreamLedgers, now: now),
            court: LawCourtScreen.load(target: target, records: records),
            dream: LawDreamScreen.make(
                file: file, ledgers: dreamLedgers, writeDenials: dreamTargets.compactMap { $0.writeDenial()?.message }),
            credibility: LawCredibilityScreen(records: records, period: input?.credibilityPeriod ?? .all, now: now),
            // 검색어가 없으면 이 원장의 기록만 쓴다(전신 색인을 읽지 않는다).
            records: LawRecordList.load(
                target: target, filter: input?.recordFilter ?? LawRecordListFilter(), records: records),
            recordDetail: selected.flatMap { LawRecordDetail.load(id: $0, target: target, records: records) },
            batchChanges: batch.map { LawDreamBatchChanges.of(batch: $0, ledgers: dreamLedgers) } ?? [])
    }

    /// 저장소 개요·world 고르기 표시. ledger 3 원장은 저장소(git)로 살피지 않는다 — 저장소 위키가 아니다.
    static func repository(worlds: [LedgerWorld], rootURL: URL?, worldName: String?) -> LedgerRepositorySnapshot {
        let registry = (try? FleetStore().load()) ?? FleetRegistry()
        let doctor = FleetDiagnostics.doctor(registry: registry)
        let catalog = catalog(config: LedgerConfig.load())
        let items = RepositoryUIPresentation.pickerItems(
            worlds: worlds, registry: registry, doctor: doctor, catalog: catalog)
        let inspect = worldName.map { !catalog.isLedgerThree($0) } ?? true
        let identity = inspect ? rootURL.flatMap { GitRepositoryInspector.inspect(worldRoot: $0.path) } : nil
        let summary = identity.flatMap { identity in
            rootURL.map { RepositorySummaryContract(identity: identity, store: LedgerStore(root: $0), peerWorlds: worlds) }
        }
        return LedgerRepositorySnapshot(pickerItems: items, identity: identity, summary: summary)
    }
}
