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
    static let defaultLedgerWorldName = "agent-law"

    private static func preferredRepositoryWorld(config: LedgerConfig) -> String? {
        let registry = (try? FleetStore().load()) ?? FleetRegistry()
        let doctor = FleetDiagnostics.doctor(registry: registry)
        return RepositoryUIPresentation.preferredRepositoryWorldName(
            worlds: config.effectiveWorlds, registry: registry, doctor: doctor)
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

    func refresh() {
        applyControlFile()
        maybeRecheckCLI()   // 원장 무변경으로 조기 반환하기 전에 — 유휴 앱에서도 드리프트를 잡는다

        // CLI `world use` 로 밖에서 세계관이 바뀌면 앱도 따라간다 (설정 파일이 정본)
        let config = LedgerConfig.load()
        let executionContext = openedRepositoryPath.flatMap {
            RepositoryContext.resolve(cwd: $0, config: config)
        }
        let selectedWorld = executionContext?.world ?? config.current
        let refreshedWorlds = Self.mergedWorlds(
            config.effectiveWorlds, executionWorld: executionContext?.world)
        var worldChanged = false
        if selectedWorld.map({ URL(fileURLWithPath: $0.rootPath) }) != rootURL {
            rootURL = selectedWorld.map { URL(fileURLWithPath: $0.rootPath) }
            selectedDocumentID = nil
            scanCache = LedgerStore.ScanCache()
            worldChanged = true
        }
        if worlds != refreshedWorlds || currentWorldName != selectedWorld?.name {
            worlds = refreshedWorlds
            currentWorldName = selectedWorld?.name
            worldChanged = true
        }
        guard let store else {
            objects = []
            return
        }
        if isLedgerThreeWorld {
            // ledger 3 원장 — 읽기 전용 투영으로 같은 화면에 싣는다(결정 0007).
            let projected = ledgerThreeObjects(root: store.root)
            guard projected.map(\.id) != objects.map(\.id) || worldChanged else { return }
            objects = projected
        } else {
            let result = store.scan(cache: &scanCache)
            guard result.changed || objects.isEmpty || worldChanged else { return }  // 무변경 → 렌더 무효화 없음
            objects = result.objects
        }
        rebuildDerived(store: store)
        refreshRepositoryPresentation()
        publishState()
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
