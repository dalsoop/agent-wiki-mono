import Foundation

public struct CityLayoutMetrics: Sendable, Equatable {
    public var gap: Float
    public var pad: Float
    public var street: Float
    public var maxRow: Float
    public var lot: Float

    public static let standard = CityLayoutMetrics(gap: 2.4, pad: 2.8, street: 2.6, maxRow: 40, lot: 1.15)

    public init(gap: Float, pad: Float, street: Float, maxRow: Float, lot: Float) {
        self.gap = gap
        self.pad = pad
        self.street = street
        self.maxRow = maxRow
        self.lot = lot
    }
}

/// App-owned inventory plus optional live-path aliases. Layout stays in the kit.
public struct CityCatalog: Sendable, Equatable {
    public var items: [CityItem]
    public var edges: [CityEdge]
    public var aliases: [String: String]

    public init(items: [CityItem] = [], edges: [CityEdge] = [], aliases: [String: String] = [:]) {
        self.items = items
        self.edges = edges
        self.aliases = aliases
    }

    public mutating func add(_ item: CityItem) {
        items.append(item)
    }

    public func resolving(_ id: String) -> String {
        aliases[id] ?? id
    }

    public func world(
        liveIds: Set<String> = [],
        filter: CityFilter = .all,
        query: CityQuery = .all,
        hopPaths: [[String]] = [],
        metrics: CityLayoutMetrics = .standard
    ) -> CityWorld {
        let live = Set(liveIds.map(resolving))
        let edges = self.edges.map { $0.resolving(aliases) }
        var world = CityLayout.world(
            items: items,
            liveIds: live,
            edges: edges,
            filter: filter,
            query: query,
            metrics: metrics
        )
        if !hopPaths.isEmpty {
            world.particlePaths = CityLayout.paths(
                hopPaths.map { $0.map(resolving) },
                buildings: world.buildingById
            )
        }
        return world
    }

    public func uses(of id: String) -> [String] {
        let canonical = resolving(id)
        return CityRelations.index(edges.map { $0.resolving(aliases) }).uses[canonical] ?? []
    }

    public func usedBy(of id: String) -> [String] {
        let canonical = resolving(id)
        return CityRelations.index(edges.map { $0.resolving(aliases) }).usedBy[canonical] ?? []
    }
}
