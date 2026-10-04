import AppKit
import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

extension LedgerModel {
    func applyLaunchConfiguration() {
        var config = LedgerConfig.load()
        let explicitPath = RepositoryLaunchContext.explicitPath(
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: ProcessInfo.processInfo.environment,
            bundledSourceDirectory: Bundle.main.object(
                forInfoDictionaryKey: "SASourceDirectory") as? String,
            currentDirectory: FileManager.default.currentDirectoryPath)
        let executionContext = explicitPath.flatMap {
            RepositoryContext.resolve(cwd: $0, config: config)
        }
        // 기본 원장은 agent-law 다(agent-wiki-mono 결정 0007). 설정의 current 가 비었거나 등록되지 않은 이름이면
        // agent-law 를 연다. 2026-10-04 실측: 사라진 current(test-throwaway)를 첫 world 로 대신 열고, 쓰지도 않을
        // fleet 진단이 문서 폴더의 repo world 까지 훑다가 파일 접근 허용 창을 띄워 메인 스레드가 멈췄다.
        let currentIsRegistered = config.currentWorld.map { name in
            config.effectiveWorlds.contains(where: { $0.name == name })
        } ?? false
        if executionContext == nil, !currentIsRegistered,
           config.effectiveWorlds.contains(where: { $0.name == Self.defaultLedgerWorldName }) {
            config.currentWorld = Self.defaultLedgerWorldName
            try? config.save()
        }
        // 첫 기동(또는 current 가 비었을 때)에만 repo world 를 기본으로 고른다.
        // fleet 진단(원장 폴더 파일 수 세기)은 이때만 돌린다 — 매 기동 메인 스레드에서 돌리지 않는다.
        // 사용자가 **명시적으로** 개인·실험 world 를 고른 것을 되돌리지 않는다 —
        // 실측 2026-08-11: CLI 로 person-yun-jeonghan 을 세우고 앱을 띄우면,
        // 이 조건문이 "repo 그룹이 아니면 → repo 로 강제 전환" 하면서 config 를
        // 덮어써 개인 world 화면을 못 봤다. "앱이 사용자보다 안다"는 전제가 함정이다.
        if executionContext == nil,
           (config.current?.name.isEmpty ?? true),
           let preferred = Self.preferredRepositoryWorld(config: config) {
            config.currentWorld = preferred
            try? config.save()
        }
        openedRepositoryPath = executionContext?.identity.worktreePath
        worlds = Self.mergedWorlds(
            config.effectiveWorlds, executionWorld: executionContext?.world)
        currentWorldName = executionContext?.world.name ?? config.current?.name
        rootURL = executionContext.map { URL(fileURLWithPath: $0.world.rootPath) }
            ?? config.current.map { URL(fileURLWithPath: $0.rootPath) }
        refresh()
        area = .wiki
        destination = .overview
        session.refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in LedgerModel.shared?.refresh() }
        }
    }

    /// 결정 0007 의 기본 원장.
    static let defaultLedgerWorldName = LawLedgerDefaults.sharedWorldName

    private static func preferredRepositoryWorld(config: LedgerConfig) -> String? {
        let registry = (try? FleetStore().load()) ?? FleetRegistry()
        let doctor = FleetDiagnostics.doctor(registry: registry)
        return RepositoryUIPresentation.preferredRepositoryWorldName(
            worlds: config.effectiveWorlds, registry: registry, doctor: doctor,
            catalog: LedgerBackgroundReader.catalog(config: config))
    }

    func switchWorld(_ world: LedgerWorld) {
        var config = LedgerConfig.load()
        let path = URL(fileURLWithPath: world.rootPath).standardizedFileURL.path
        if let registered = config.effectiveWorlds.first(where: {
            URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == path
        }) {
            openedRepositoryPath = nil
            config.worlds = config.effectiveWorlds
            config.currentWorld = registered.name
            try? config.save()
        } else if let context = RepositoryContext.resolve(
            cwd: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            config: config
        ) {
            openedRepositoryPath = context.identity.worktreePath
        }
        worlds = Self.mergedWorlds(config.effectiveWorlds, executionWorld: world)
        currentWorldName = world.name
        rootURL = URL(fileURLWithPath: path)
        selectedDocumentID = nil
        destination = .overview
        law = LedgerLawUIState()  // 원장 판정·표시 모델은 배경 읽기가 새 원장으로 다시 채운다
        session.refresh.forceLawReload = true
        promotionPreview = nil
        promotionResult = nil
        promotionMessage = nil
        refresh()
        refreshProtectionStatus()
    }

    nonisolated static func mergedWorlds(
        _ configured: [LedgerWorld], executionWorld: LedgerWorld?
    ) -> [LedgerWorld] {
        guard let executionWorld else { return configured }
        let executionPath = URL(fileURLWithPath: executionWorld.rootPath).standardizedFileURL.path
        if configured.contains(where: {
            URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == executionPath
        }) { return configured }
        return [executionWorld] + configured
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "이 폴더에 기록"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootURL = url
        do { try FileManager.default.createDirectory(
            at: url.appendingPathComponent("objects"), withIntermediateDirectories: true) } catch { _ = error }
        try? LedgerConfig(rootPath: url.path).save()
        refresh()
    }

    /// 앱 조종 컨트롤 파일 적용 (agent-wiki app …) — orca 식 공식 제어 표면.
    private func applyControlFile() {
        let path = StateRootKit.path(".memo-citation-ledger/control.json")
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let payload: [String: String]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
            payload = parsed
        } catch {
            return
        }
        try? FileManager.default.removeItem(atPath: path)
        let argument = payload["argument"] ?? ""
        switch payload["command"] {
        case "area":
            // 키→영역 매핑은 LedgerArea(controlKey:) 하나로 — CLI 검증(LedgerAreaKey.all)과 SSOT 공유.
            if let area = LedgerArea(controlKey: argument) { recordNavigation(); self.area = area }
        case "destination":
            if RepositoryDestinationKey.isValid(argument),
               let destination = RepositoryDestination(rawValue: argument) {
                selectDestination(destination)
            }
        case "jump":
            jump(toObject: argument)
        case "select":
            selectedDocumentID = argument
        default: break
        }
        publishState()
    }

    /// 화면 갱신. 설정·원장 폴더 읽기는 배경(`LedgerBackgroundReader.read`)에서 하고 결과만 메인에 반영한다 —
    /// 2초 타이머가 메인 스레드에서 원장 폴더를 훑지 않는다. 한 번에 하나만 돌고, 도는 중·반영 중에 들어온 요청은
    /// 끝난 뒤 한 번만 더 돈다(`LedgerRefreshState`).
    /// - Parameter then: 결과를 반영한 뒤 메인에서 부를 일(쓰기 직후 새 기록 고르기 등). 이 호출 뒤에 시작한 읽기를 기다린다.
    func refresh(then: (@MainActor () -> Void)? = nil) {
        applyControlFile()
        maybeRecheckCLI()   // 원장 무변경으로 조기 반환하기 전에 — 유휴 앱에서도 드리프트를 잡는다
        guard session.refresh.request(then: then) else { return }
        let input = LedgerRefreshInput(
            openedRepositoryPath: openedRepositoryPath, rootURL: rootURL, currentWorldName: currentWorldName,
            worlds: worlds, objectIDs: objects.map(\.id), scanCache: scanCache, lawFingerprint: law.fingerprint,
            forceLawReload: session.refresh.forceLawReload, lawLoaded: law.contents != nil, recordFilter: law.recordFilter,
            credibilityPeriod: law.credibilityPeriod, selectedRecordID: law.selectedRecordID,
            selectedBatch: law.selectedBatch)
        session.refresh.forceLawReload = false
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = LedgerBackgroundReader.read(input)
            await self?.applyRefresh(snapshot)
        }
    }

    /// 배경 읽기 결과를 반영한다. 읽는 사이 메인에서 원장을 바꿨으면(world 전환) 버리고 다시 읽는다.
    /// 반영 중 표시 모델 다시 읽기가 요청되면(`reloadLawScreens`) 끝에서 한 번만 돈다 — 맡은 일(completions)을 잃지 않는다.
    private func applyRefresh(_ snapshot: LedgerRefreshSnapshot) {
        let completions = session.refresh.beginApply()
        let input = snapshot.input
        guard input.rootURL == rootURL, input.currentWorldName == currentWorldName else {
            session.refresh.discard(completions)
            refresh()
            return
        }
        if snapshot.rootChanged {
            rootURL = snapshot.rootURL
            selectedDocumentID = nil
            law = LedgerLawUIState()
        }
        if worlds != snapshot.worlds || currentWorldName != snapshot.selectedWorldName {
            worlds = snapshot.worlds
            currentWorldName = snapshot.selectedWorldName
        }
        scanCache = snapshot.scanCache
        applyLawKind(snapshot.kind)
        if let fingerprint = snapshot.lawFingerprint { law.fingerprint = fingerprint }
        if let screens = snapshot.law { applyLawScreens(screens, for: input) }
        if let objects = snapshot.objects {
            self.objects = objects
            if let store { rebuildDerived(store: store) }
            refreshRepositoryPresentation()
            publishState()
        }
        for completion in completions { completion() }
        if session.refresh.endApply() { refresh() }
    }

    /// 파생 인덱스 재구축 — 객체가 실제로 바뀔 때 한 번만 (옵시디언 MetadataCache 방식).
    private func rebuildDerived(store: LedgerStore) {
        let retracted = Set(objects.compactMap(\.retracts))
        let superseded = Set(objects.compactMap(\.supersedes))
        var base: [(document: LedgerDocument, isDeleted: Bool)] = []
        var strengths: [String: EvidenceStrength] = [:]
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        for object in objects where !superseded.contains(object.id) && object.retracts == nil {
            var chain: [LedgerObject] = []
            var current: LedgerObject? = object
            while let node = current, chain.count < 1000 {
                chain.append(node)
                current = node.supersedes.flatMap { byID[$0] }
            }
            base.append((LedgerDocument(head: object, versions: chain), retracted.contains(object.id)))
            strengths[object.id] = store.strength(objects, of: object)
        }
        baseDocuments = base
        documentByHead = Dictionary(uniqueKeysWithValues: base.map { ($0.document.head.id, $0.document) })
        strengthByHead = strengths
        // 분류 인덱스 — CLI 와 동일한 Core 구현 사용
        let classification = LedgerClassification(objects: objects)
        domainIndex = classification.domain
        kindIndex = classification.kind
        knowledgeIndex = classification.knowledge
        // 연합 간선
        var authorOf: [String: String] = [:]
        for object in objects { authorOf[object.id] = object.author }
        var counts: [String: Int] = [:]
        for object in objects {
            for cite in object.cites {
                guard let cited = authorOf[cite.id], cited != object.author else { continue }
                counts["\(object.author)\u{1}\(cited)", default: 0] += 1
            }
        }
        cachedAgentEdges = counts.map { key, count in
            let parts = key.split(separator: "\u{1}")
            return AgentEdge(from: String(parts[0]), to: String(parts[1]), count: count)
        }.sorted { $0.count > $1.count }
    }
}
