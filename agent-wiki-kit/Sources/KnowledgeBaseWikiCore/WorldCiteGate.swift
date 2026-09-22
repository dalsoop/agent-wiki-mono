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

/// 인용은 자기 world 와 상위(parent 사슬)만. 하위·형제는 거부.
public enum WorldCiteGate: Sendable {
    public static func evaluate(
        currentWorld: String,
        citedID: String,
        citedWorld: String,
        catalog: WorldBindingCatalog
    ) -> WorldCiteDenial? {
        if citedWorld == currentWorld { return nil }
        if catalog.isAncestor(citedWorld, of: currentWorld) { return nil }

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

public enum WorldSearchScope: Sendable {
    /// 현재 world + parent + parent.parent. 형제·하위는 제외.
    public static func names(current: String, catalog: WorldBindingCatalog) -> [String] {
        var ordered = [current]
        for ancestor in catalog.ancestorNames(of: current) {
            if !ordered.contains(ancestor) { ordered.append(ancestor) }
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
