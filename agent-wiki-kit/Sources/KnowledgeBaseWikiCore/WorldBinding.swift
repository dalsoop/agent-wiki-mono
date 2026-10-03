import Foundation

/// CLI world 목록 헤더는 `rawValue` 를 쓴다(동작 유지). GUI 는 `groupTitle`.
public typealias WikiBoundLayer = WikiWorldLayer

public struct BoundWorld: Codable, Equatable, Sendable {
    public var name: String
    public var rootPath: String
    public var layer: String?
    public var parent: String?
    /// 사람용 표시 이름 — 없으면 slug(name) 그대로.
    public var display: String?
    /// ledger 3 원장 키(`LedgerKeyFormat`). 등록 후 바꿀 수 없다. 근거: 결정 0007.
    public var key: String?
    /// 이 원장이 이어받은 옛 원장(world 이름) 하나. 전신은 사슬이 아니다. parent 와 별개.
    public var predecessor: String?

    /// 사람용 표시 이름 (display 가 있으면 사용, 없으면 표준 기본값 매핑 또는 name).
    public var displayName: String {
        display ?? WorldDisplayNameMapper.defaultDisplayName(for: name)
    }

    public init(
        name: String, rootPath: String, layer: String? = nil, parent: String? = nil,
        display: String? = nil, key: String? = nil, predecessor: String? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.layer = layer
        self.parent = parent
        self.display = display
        self.key = key
        self.predecessor = predecessor
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(rootPath, forKey: .rootPath)
        try container.encodeIfPresent(layer, forKey: .layer)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(display, forKey: .display)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(predecessor, forKey: .predecessor)
    }
}

public struct BoundLedgerFile: Codable, Equatable, Sendable {
    public var rootPath: String?
    public var worlds: [BoundWorld]?
    public var currentWorld: String?
    /// 테넌트 slug → world 이름. 정본은 이 호스트 설정. 근거: 결정 0007.
    public var tenantMap: [String: String]?
    /// 등록된 기기 키 목록(형식은 `LedgerKeyFormat`, 등록 후 불변).
    public var devices: [String]?
    /// 이 기기의 기기 키.
    public var currentDevice: String?
    /// 드리밍 기기 키(하나).
    public var dreamDevice: String?
    /// agent-law R2 엔드포인트·버킷(비밀 아님). 키는 키체인에만 둔다. 근거: docs/security.md "R2 와 세션".
    public var lawStorage: LawStorageSettings?
    /// 심급(중재자 후보·대법원 이의 기간). 비우면 기본값. 근거: docs/business-rules.md "심급제".
    public var court: LawCourtSettings?
    /// 앱이 주입. Codable 에는 안 실린다.
    public var fallbackWorldName: String

    enum CodingKeys: String, CodingKey {
        case rootPath, worlds, currentWorld, tenantMap, devices, currentDevice, dreamDevice, lawStorage, court
    }

    public init(
        rootPath: String? = nil,
        worlds: [BoundWorld]? = nil,
        currentWorld: String? = nil,
        tenantMap: [String: String]? = nil,
        devices: [String]? = nil,
        currentDevice: String? = nil,
        dreamDevice: String? = nil,
        lawStorage: LawStorageSettings? = nil,
        court: LawCourtSettings? = nil,
        fallbackWorldName: String = "gujo-wiki"
    ) {
        self.rootPath = rootPath
        self.worlds = worlds
        self.currentWorld = currentWorld
        self.tenantMap = tenantMap
        self.devices = devices
        self.currentDevice = currentDevice
        self.dreamDevice = dreamDevice
        self.lawStorage = lawStorage
        self.court = court
        self.fallbackWorldName = fallbackWorldName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath)
        worlds = try container.decodeIfPresent([BoundWorld].self, forKey: .worlds)
        currentWorld = try container.decodeIfPresent(String.self, forKey: .currentWorld)
        tenantMap = try container.decodeIfPresent([String: String].self, forKey: .tenantMap)
        devices = try container.decodeIfPresent([String].self, forKey: .devices)
        currentDevice = try container.decodeIfPresent(String.self, forKey: .currentDevice)
        dreamDevice = try container.decodeIfPresent(String.self, forKey: .dreamDevice)
        lawStorage = try container.decodeIfPresent(LawStorageSettings.self, forKey: .lawStorage)
        court = try container.decodeIfPresent(LawCourtSettings.self, forKey: .court)
        fallbackWorldName = "gujo-wiki"
    }

    public var effectiveWorlds: [BoundWorld] {
        if let worlds, !worlds.isEmpty { return worlds }
        if let rootPath { return [BoundWorld(name: fallbackWorldName, rootPath: rootPath)] }
        return []
    }
}

public enum WorldLayerInference: Sendable {
    public static func infer(name: String, rootPath: String) -> WikiWorldLayer {
        WikiWorldPresentation.classify(name: name, rootPath: rootPath)
    }

    public static func resolved(explicit: String?, name: String, rootPath: String) -> WikiWorldLayer {
        if let explicit, let layer = WikiWorldLayer(rawValue: explicit) {
            return layer
        }
        return infer(name: name, rootPath: rootPath)
    }
}

public struct WorldBindingCatalog: Equatable, Sendable {
    public var worlds: [BoundWorld]

    public init(worlds: [BoundWorld]) {
        self.worlds = worlds
    }

    public func world(named name: String) -> BoundWorld? {
        worlds.first { $0.name == name }
    }

    public func resolvedLayer(of name: String) -> WikiWorldLayer? {
        guard let world = world(named: name) else { return nil }
        return WorldLayerInference.resolved(explicit: world.layer, name: world.name, rootPath: world.rootPath)
    }

    public func parentName(of name: String) -> String? {
        world(named: name)?.parent
    }

    /// 자기 제외, parent → parent.parent … (순환 절단).
    public func ancestorNames(of name: String) -> [String] {
        var result: [String] = []
        var seen: Set<String> = [name]
        var current = parentName(of: name)
        while let parent = current, !seen.contains(parent) {
            seen.insert(parent)
            result.append(parent)
            current = parentName(of: parent)
        }
        return result
    }

    public func isAncestor(_ candidate: String, of name: String) -> Bool {
        ancestorNames(of: name).contains(candidate)
    }

    /// 이 world 가 선언한 전신(하나). 전신의 전신은 따라가지 않는다.
    public func predecessorName(of name: String) -> String? {
        guard let predecessor = world(named: name)?.predecessor, predecessor != name else { return nil }
        return predecessor
    }

    /// 이 world 를 전신으로 선언한 world 들(후신).
    public func successorNames(of name: String) -> [String] {
        worlds.filter { $0.name != name && $0.predecessor == name }.map(\.name)
    }

    /// 다른 world 의 전신으로 지정된 world 는 보관됨(모든 쓰기 거부). 근거: 결정 0007.
    public func isArchived(_ name: String) -> Bool {
        !successorNames(of: name).isEmpty
    }

    /// ledger 3 world = 원장 키나 전신을 가진 world. 기기 키 판정은 이 world 에만 적용한다.
    public func isLedgerThree(_ name: String) -> Bool {
        guard let world = world(named: name) else { return false }
        return world.key != nil || world.predecessor != nil
    }

    public static func merging(refs: [(name: String, rootPath: String)], bindings: [BoundWorld]) -> WorldBindingCatalog {
        let byName = Dictionary(uniqueKeysWithValues: bindings.map { ($0.name, $0) })
        let merged = refs.map { ref in
            let extra = byName[ref.name]
            return BoundWorld(
                name: ref.name,
                rootPath: ref.rootPath,
                layer: extra?.layer,
                parent: extra?.parent,
                display: extra?.display,
                key: extra?.key,
                predecessor: extra?.predecessor)
        }
        return WorldBindingCatalog(worlds: merged)
    }
}

public enum WorldTenantBinding {
    public static func validateTenantParent(
        parentName: String,
        catalog: WorldBindingCatalog
    ) -> String? {
        guard let parent = catalog.world(named: parentName) else {
            return "unknown parent world: \(parentName)"
        }
        let layer = WorldLayerInference.resolved(
            explicit: parent.layer, name: parent.name, rootPath: parent.rootPath)
        guard layer == .remoteShared else {
            return "--parent requires remoteShared layer: \(parentName) is \(layer.rawValue)"
        }
        return nil
    }

    public static func requireTenantFlags(layer: String?, parent: String?) -> String? {
        if layer == nil, parent == nil { return nil }
        if let layer, layer != WikiWorldLayer.tenant.rawValue {
            return "--layer allows tenant only (got: \(layer))"
        }
        if layer == WikiWorldLayer.tenant.rawValue, parent == nil {
            return "tenant world requires --parent <shared-world>"
        }
        if parent != nil, layer != WikiWorldLayer.tenant.rawValue {
            return "--parent requires --layer tenant"
        }
        return nil
    }
}

public enum WorldConfigStore {
    public static func load(from url: URL) -> BoundLedgerFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return BoundLedgerFile()
        }
        do {
            return try JSONDecoder().decode(BoundLedgerFile.self, from: data)
        } catch {
            return BoundLedgerFile()
        }
    }

    public static func save(_ file: BoundLedgerFile, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    /// worlds 목록을 갈아끼우되 같은 이름의 layer/parent/display 는 유지한다.
    /// 원장 키와 전신은 불변이므로 새 항목에 값이 없으면 항상 옛 값을 유지한다.
    public static func replacingWorlds(
        _ file: BoundLedgerFile,
        with worlds: [BoundWorld]
    ) -> BoundLedgerFile {
        let previous = Dictionary(
            uniqueKeysWithValues: file.effectiveWorlds.map { ($0.name, $0) })
        let merged = worlds.map { world in
            guard let old = previous[world.name] else { return world }
            var next = world
            next.key = world.key ?? old.key
            next.predecessor = world.predecessor ?? old.predecessor
            guard world.layer == nil, world.parent == nil, world.display == nil else { return next }
            next.layer = old.layer
            next.parent = old.parent
            next.display = old.display
            return next
        }
        var next = file
        next.worlds = merged
        return next
    }
}

/// world 사람용 Display 이름 매핑 SSOT.
public enum WorldDisplayNameMapper {
    public static let standardDisplayNames: [String: String] = [
        "gujo-wiki": "조직 공유 원장 (Gujo Shared Ledger)",
        "person-yun-jeonghan": "윤정한 개인 주관 일지 (Jeonghan Personal Ledger)",
    ]

    public static func defaultDisplayName(for worldName: String) -> String {
        standardDisplayNames[worldName] ?? worldName
    }
}

public struct WorldListJSONItem: Codable, Equatable, Sendable {
    public var name: String
    public var rootPath: String
    public var layer: String
    public var parent: String?
    public var title: String
    public var subtitle: String
    public var selected: Bool
    /// 사람용 표시 이름 — 기본값은 slug(name). 구버전 JSON 은 키가 없어 nil.
    public var display: String?
    /// 사람용 표시 이름(정본 필드).
    public var displayName: String

    public init(
        name: String,
        rootPath: String,
        layer: String,
        parent: String? = nil,
        title: String,
        subtitle: String,
        selected: Bool,
        display: String? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.layer = layer
        self.parent = parent
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        let resolved = display ?? WorldDisplayNameMapper.defaultDisplayName(for: name)
        self.display = resolved
        self.displayName = resolved
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.rootPath = try c.decode(String.self, forKey: .rootPath)
        self.layer = try c.decode(String.self, forKey: .layer)
        self.parent = try c.decodeIfPresent(String.self, forKey: .parent)
        self.title = try c.decode(String.self, forKey: .title)
        self.subtitle = try c.decode(String.self, forKey: .subtitle)
        self.selected = try c.decode(Bool.self, forKey: .selected)
        let decodedDisplay = try c.decodeIfPresent(String.self, forKey: .display)
        let decodedDisplayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        let resolved = decodedDisplayName ?? decodedDisplay ?? WorldDisplayNameMapper.defaultDisplayName(for: self.name)
        self.display = decodedDisplay ?? resolved
        self.displayName = resolved
    }
}

public enum WorldListPresentation {
    public static func items(
        catalog: WorldBindingCatalog,
        selectedName: String?
    ) -> [WorldListJSONItem] {
        catalog.worlds.map { world in
            let layer = WorldLayerInference.resolved(
                explicit: world.layer, name: world.name, rootPath: world.rootPath)
            let resolvedDisplay = world.display ?? WorldDisplayNameMapper.defaultDisplayName(for: world.name)
            return WorldListJSONItem(
                name: world.name,
                rootPath: world.rootPath,
                layer: layer.rawValue,
                parent: world.parent,
                title: world.name,
                subtitle: (world.rootPath as NSString).abbreviatingWithTildeInPath,
                selected: world.name == selectedName,
                display: resolvedDisplay)
        }
        .sorted {
            let left = WikiWorldLayer(rawValue: $0.layer)?.sortIndex ?? 99
            let right = WikiWorldLayer(rawValue: $1.layer)?.sortIndex ?? 99
            if left != right { return left < right }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public static func plainText(items: [WorldListJSONItem]) -> String {
        var lines: [String] = []
        for layer in WikiWorldLayer.allCases {
            let rows = items.filter { $0.layer == layer.rawValue }
            guard !rows.isEmpty else { continue }
            lines.append(layer.rawValue)
            for row in rows {
                let mark = row.selected ? "*" : " "
                let parent = row.parent.map { "  parent=\($0)" } ?? ""
                // display 는 뒤에 덧붙인다 — slug 와 같으면(기본값) 기존 포맷 그대로.
                let display = row.display.flatMap { $0 == row.name ? nil : "  display=\($0)" } ?? ""
                lines.append("\(mark) \(row.title)  [\(row.name)]  \(row.rootPath)\(parent)\(display)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct WorldMutationFailure: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public enum WorldMutation {
    public static func adding(
        to file: BoundLedgerFile,
        name: String,
        path: String,
        layer: String?,
        parent: String?,
        display: String? = nil,
        key: String? = nil,
        predecessor: String? = nil
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        if let error = WorldTenantBinding.requireTenantFlags(layer: layer, parent: parent) {
            return .failure(WorldMutationFailure(error))
        }
        let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
        if let parent, let error = WorldTenantBinding.validateTenantParent(
            parentName: parent, catalog: catalog)
        {
            return .failure(WorldMutationFailure(error))
        }
        let existing = catalog.world(named: name)
        if let error = WorldLedgerKeyBinding.validate(
            worldName: name, key: key, existing: existing, catalog: catalog)
        {
            return .failure(WorldMutationFailure(error))
        }
        let resolvedKey = key ?? existing?.key
        let resolvedPredecessor = predecessor ?? existing?.predecessor
        var worlds = file.effectiveWorlds
        worlds.removeAll { $0.name == name }
        worlds.append(BoundWorld(
            name: name, rootPath: path, layer: layer, parent: parent, display: display,
            key: resolvedKey, predecessor: resolvedPredecessor))
        if let error = WorldPredecessorBinding.validate(
            worldName: name,
            requested: predecessor,
            existing: existing?.predecessor,
            catalog: WorldBindingCatalog(worlds: worlds))
        {
            return .failure(WorldMutationFailure(error))
        }
        var next = file
        next.worlds = worlds
        return .success(next)
    }

    public static func settingLayer(
        of name: String,
        in file: BoundLedgerFile,
        layer: String,
        parent: String?
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        if let error = WorldTenantBinding.requireTenantFlags(layer: layer, parent: parent) {
            return .failure(WorldMutationFailure(error))
        }
        let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
        if let parent, let error = WorldTenantBinding.validateTenantParent(
            parentName: parent, catalog: catalog)
        {
            return .failure(WorldMutationFailure(error))
        }
        var worlds = file.effectiveWorlds
        guard let index = worlds.firstIndex(where: { $0.name == name }) else {
            return .failure(WorldMutationFailure("없는 세계관: \(name)"))
        }
        worlds[index].layer = layer
        worlds[index].parent = parent
        var next = file
        next.worlds = worlds
        return .success(next)
    }
}

public enum WorldCatalogLoader {
    public static func merging(file: BoundLedgerFile, config: LedgerConfig) -> WorldBindingCatalog {
        if !config.effectiveWorlds.isEmpty {
            var catalog = WorldBindingCatalog.merging(
                refs: config.effectiveWorlds.map { (name: $0.name, rootPath: $0.rootPath) },
                bindings: file.effectiveWorlds)
            // display 는 binding 파일이 우선, 없으면 config(manifest) 등록값.
            let configDisplay = Dictionary(
                uniqueKeysWithValues: config.effectiveWorlds.map { ($0.name, $0.display) })
            for index in catalog.worlds.indices where catalog.worlds[index].display == nil {
                catalog.worlds[index].display = configDisplay[catalog.worlds[index].name] ?? nil
            }
            return catalog
        }
        return WorldBindingCatalog(worlds: file.effectiveWorlds)
    }

    public static func overlayingCurrent(_ current: LedgerWorld, onto catalog: WorldBindingCatalog, file: BoundLedgerFile) -> WorldBindingCatalog {
        var next = catalog
        if next.world(named: current.name) == nil {
            let extra = file.effectiveWorlds.first { $0.name == current.name }
            next.worlds.append(
                BoundWorld(
                    name: current.name,
                    rootPath: current.rootPath,
                    layer: extra?.layer,
                    parent: extra?.parent,
                    display: extra?.display ?? current.display,
                    key: extra?.key,
                    predecessor: extra?.predecessor))
        }
        return next
    }
}

public enum WorldBoundBootstrap {
    public static func load(
        from url: URL,
        overlay config: LedgerConfig,
        fallbackWorldName: String = "gujo-wiki"
    ) -> BoundLedgerFile {
        var file = WorldConfigStore.load(from: url)
        file.fallbackWorldName = fallbackWorldName
        if file.effectiveWorlds.isEmpty {
            file.rootPath = config.rootPath
            file.currentWorld = config.currentWorld
            file.worlds = config.effectiveWorlds.map {
                BoundWorld(name: $0.name, rootPath: $0.rootPath, display: $0.display)
            }
        }
        return file
    }
}
