import Foundation

public struct WorldCiteDenial: Equatable, Sendable {
    public var citedID: String
    public var citedWorld: String
    public var currentWorld: String
    public var message: String

    public init(citedID: String, citedWorld: String, currentWorld: String, message: String) {
        self.citedID = citedID
        self.citedWorld = citedWorld
        self.currentWorld = currentWorld
        self.message = message
    }
}

/// 인용은 자기 world, 상위(parent 사슬), 그리고 그 각각의 전신만. 하위·형제와 그 전신은 거부.
public enum WorldCiteGate: Sendable {
    public static func evaluate(
        currentWorld: String,
        citedID: String,
        citedWorld: String,
        catalog: WorldBindingCatalog
    ) -> WorldCiteDenial? {
        if citedWorld == currentWorld { return nil }
        if WorldSearchScope.entries(current: currentWorld, catalog: catalog)
            .contains(where: { $0.name == citedWorld })
        {
            return nil
        }

        let citedLayer = catalog.resolvedLayer(of: citedWorld)?.rawValue ?? "?"
        let currentLayer = catalog.resolvedLayer(of: currentWorld)?.rawValue ?? "?"
        let currentParent = catalog.parentName(of: currentWorld)
        let citedParent = catalog.parentName(of: citedWorld)
        let sibling = currentParent != nil && currentParent == citedParent
            && catalog.resolvedLayer(of: currentWorld) == .tenant
            && catalog.resolvedLayer(of: citedWorld) == .tenant

        let message: String
        if sibling {
            message = "sibling tenant cite refused: \(citedID) in world '\(citedWorld)'"
        } else if catalog.isAncestor(currentWorld, of: citedWorld)
                    || (currentLayer == WikiWorldLayer.remoteShared.rawValue
                        && citedLayer == WikiWorldLayer.tenant.rawValue)
        {
            message = "cite is upward-only: world '\(currentWorld)'(\(currentLayer)) cannot cite \(citedID) in lower world '\(citedWorld)'(\(citedLayer))"
        } else if catalog.isArchived(citedWorld) {
            let successors = catalog.successorNames(of: citedWorld).joined(separator: "', '")
            message = "predecessor cite refused: \(citedID) is in '\(citedWorld)' (predecessor of '\(successors)'), outside the cite scope of '\(currentWorld)'"
        } else {
            message = "cite allows same world and ancestors only: \(citedID) is in '\(citedWorld)'(\(citedLayer))"
        }
        return WorldCiteDenial(
            citedID: citedID,
            citedWorld: citedWorld,
            currentWorld: currentWorld,
            message: message)
    }

    /// `objectsByWorld[worldName] = 그 world 의 객체 id 집합`.
    public static func locateWorld(
        containing id: String,
        objectsByWorld: [String: Set<String>]
    ) -> String? {
        if let exact = objectsByWorld.first(where: { $0.value.contains(id) }) {
            return exact.key
        }
        var matches: [String] = []
        for (world, ids) in objectsByWorld {
            if ids.contains(where: { $0.hasPrefix(id) || id.hasPrefix($0) }) {
                matches.append(world)
            }
        }
        if matches.count == 1 { return matches[0] }
        return nil
    }
}

public struct WorldScopeEntry: Codable, Equatable, Sendable {
    public var name: String
    public var predecessor: Bool
    public var predecessorOf: String?

    public init(name: String, predecessor: Bool = false, predecessorOf: String? = nil) {
        self.name = name
        self.predecessor = predecessor
        self.predecessorOf = predecessorOf
    }
}

public enum WorldSearchScope: Sendable {
    /// 현재 world + parent + parent.parent. 형제·하위는 제외.
    public static func names(current: String, catalog: WorldBindingCatalog) -> [String] {
        entries(current: current, catalog: catalog).map(\.name)
    }

    /// 현재 world, 조상, 그리고 그 각각의 전신(전신의 전신은 따라가지 않음). 인용 게이트와 같은 범위.
    /// 전신 항목은 `predecessor: true` 와 그 전신을 선언한 world(`predecessorOf`)를 가진다. 근거: 결정 0007.
    public static func entries(current: String, catalog: WorldBindingCatalog) -> [WorldScopeEntry] {
        var ordered: [WorldScopeEntry] = []
        func append(_ entry: WorldScopeEntry) {
            if !ordered.contains(where: { $0.name == entry.name }) { ordered.append(entry) }
        }
        for base in [current] + catalog.ancestorNames(of: current) {
            append(WorldScopeEntry(name: base))
            if let predecessor = catalog.predecessorName(of: base) {
                append(WorldScopeEntry(name: predecessor, predecessor: true, predecessorOf: base))
            }
        }
        return ordered
    }
}

public enum WorldEnvLock: Sendable {
    public static let environmentKey = "AGENT_WIKI_WORLD"

    /// `publish` / `promotion publish` 에서 `--world` 가 env 와 다르면 거부. 조회는 허용.
    public static func denial(
        environment: [String: String],
        explicitWorld: String?,
        isWrite: Bool
    ) -> String? {
        guard isWrite else { return nil }
        guard let locked = environment[environmentKey], !locked.isEmpty else { return nil }
        guard let explicitWorld, !explicitWorld.isEmpty, explicitWorld != locked else { return nil }
        return "\(environmentKey)=\(locked) blocks --world \(explicitWorld) on publish"
    }
}

public enum WorldPromotionGate: Sendable {
    public static func canonicalTargetName(_ raw: String) -> String {
        raw == "gujo" ? "gujo-wiki" : raw
    }

    /// `--to` 가 현재 world 의 parent 사슬에 있을 때만 허용.
    /// `skipChainWhenUnbound`: parent 가 없는 repo 등 기존 승격은 등록된 `--to` 를 유지.
    public static func denial(
        currentWorld: String,
        targetWorld: String,
        catalog: WorldBindingCatalog,
        skipChainWhenUnbound: Bool = false
    ) -> String? {
        let target = canonicalTargetName(targetWorld)
        if catalog.world(named: target) == nil {
            return "unknown target world: \(target)"
        }
        if catalog.isAncestor(target, of: currentWorld) { return nil }
        if skipChainWhenUnbound, catalog.parentName(of: currentWorld) == nil { return nil }
        return "--to \(target) is not in parent chain of '\(currentWorld)'"
    }
}
