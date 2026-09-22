import Foundation

/// CodeCity packing: one ground, districts = modules, unused stays in place.
public enum CityLayout {
    public static func world(
        items: [CityItem],
        liveIds: Set<String> = [],
        edges: [CityEdge] = [],
        filter: CityFilter = .all,
        query: CityQuery = .all,
        metrics: CityLayoutMetrics = .standard
    ) -> CityWorld {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        var effective = query
        if filter != .all { effective.usage = filter }
        let visible = unique.filter { effective.matches($0, liveIds: liveIds) }

        let gap = metrics.gap
        let pad = metrics.pad
        let street = metrics.street
        let names = Array(Set(visible.map(\.district))).sorted()
        var sizes: [(String, Float, Float)] = []
        var members: [String: [CityItem]] = [:]
        var cols: [String: Int] = [:]
        for name in names {
            let list = visible.filter { $0.district == name }.sorted { lhs, rhs in
                if lhs.used != rhs.used { return !lhs.used && rhs.used }
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.label < rhs.label
            }
            let c = max(1, Int(ceil(sqrt(Double(max(list.count, 1))))))
            let r = Int(ceil(Double(max(list.count, 1)) / Double(c)))
            members[name] = list
            cols[name] = c
            sizes.append((name, Float(c) * gap + pad, Float(r) * gap + pad))
        }
        let origins = pack(sizes, street: street, maxRow: metrics.maxRow)

        var buildings: [CityBuilding] = []
        var districts: [CityDistrict] = []
        for (name, width, depth) in sizes {
            let (ox, oz) = origins[name] ?? (0, 0)
            districts.append(CityDistrict(name: name, x: ox + width / 2, z: oz + depth / 2, width: width, depth: depth))
            let list = members[name] ?? []
            let c = cols[name] ?? 1
            for (index, item) in list.enumerated() {
                let h = min(3.2, 0.4 + Float(item.weight) / 140)
                let usage: CityUsage
                if liveIds.contains(item.id) { usage = .live }
                else if item.used { usage = .used }
                else { usage = .unused }
                buildings.append(
                    CityBuilding(
                        identity: .init(
                            id: item.id,
                            label: item.label,
                            district: name,
                            role: item.role,
                            face: item.face
                        ),
                        source: .init(file: item.file, line: item.line),
                        box: .init(
                            x: ox + pad / 2 + Float(index % c) * gap,
                            y: h / 2,
                            z: oz + pad / 2 + Float(index / c) * gap,
                            width: metrics.lot,
                            height: h,
                            depth: metrics.lot
                        ),
                        usage: usage,
                        reason: usage == .live ? .livePath : item.reason
                    )
                )
            }
        }

        let byId = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
        let segments = edges.filter { byId[$0.from] != nil && byId[$0.to] != nil }
        let relations = CityRelations.index(edges)
        let needle = effective.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var labelIds = Set(buildings.filter { $0.usage != .used }.map(\.id))
        if buildings.count <= 48 {
            labelIds.formUnion(buildings.map(\.id))
        }
        if !needle.isEmpty {
            labelIds.formUnion(visible.filter { effective.matches($0, liveIds: liveIds) }.map(\.id))
        }
        labelIds.formUnion(liveIds)
        let paths: [[CityPoint]] = {
            guard !liveIds.isEmpty else { return [] }
            let hops = edges.compactMap { edge -> [CityPoint]? in
                guard let a = byId[edge.from], let b = byId[edge.to] else { return nil }
                return [
                    CityPoint(x: a.x, y: a.y + a.height / 2 + 0.18, z: a.z),
                    CityPoint(x: b.x, y: b.y + b.height / 2 + 0.18, z: b.z)
                ]
            }
            return hops
        }()

        return CityWorld(
            districts: districts,
            buildings: buildings,
            segments: segments,
            particlePaths: paths,
            bounds: bounds(districts: districts, buildings: buildings),
            usedCount: unique.filter(\.used).count,
            unusedCount: unique.filter { !$0.used }.count,
            uses: relations.uses,
            usedBy: relations.usedBy,
            labelIds: labelIds
        )
    }

    public static func pack(
        _ sizes: [(String, Float, Float)],
        street: Float,
        maxRow: Float
    ) -> [String: (Float, Float)] {
        var origins: [String: (Float, Float)] = [:]
        var x: Float = 0
        var z: Float = 0
        var rowHeight: Float = 0
        var rowWidth: Float = 0
        for (name, width, depth) in sizes {
            if rowWidth > 0 && rowWidth + street + width > maxRow {
                x = 0
                z += rowHeight + street
                rowHeight = 0
                rowWidth = 0
            }
            origins[name] = (x, z)
            x += width + street
            rowWidth = x
            rowHeight = max(rowHeight, depth)
        }
        return origins
    }

    public static func point(along path: [CityPoint], t: Float) -> CityPoint {
        guard path.count >= 2 else { return path.first ?? CityPoint(x: 0, y: 0, z: 0) }
        let clamped = min(1, max(0, t))
        let segs = path.count - 1
        let scaled = clamped * Float(segs)
        let index = min(Int(scaled), segs - 1)
        let f = scaled - Float(index)
        let a = path[index]
        let b = path[index + 1]
        return CityPoint(
            x: a.x + (b.x - a.x) * f,
            y: a.y + (b.y - a.y) * f,
            z: a.z + (b.z - a.z) * f
        )
    }

    public static func paths(_ hops: [[String]], buildings: [String: CityBuilding]) -> [[CityPoint]] {
        hops.compactMap { path in
            let pts = path.compactMap { id -> CityPoint? in
                guard let building = buildings[id] else { return nil }
                return CityPoint(x: building.x, y: building.y + building.height / 2 + 0.18, z: building.z)
            }
            return pts.count >= 2 ? pts : nil
        }
    }

    public static func districtsOverlap(_ a: CityDistrict, _ b: CityDistrict) -> Bool {
        let ax0 = a.x - a.width / 2, ax1 = a.x + a.width / 2
        let az0 = a.z - a.depth / 2, az1 = a.z + a.depth / 2
        let bx0 = b.x - b.width / 2, bx1 = b.x + b.width / 2
        let bz0 = b.z - b.depth / 2, bz1 = b.z + b.depth / 2
        return ax0 < bx1 && ax1 > bx0 && az0 < bz1 && az1 > bz0
    }

    private static func bounds(districts: [CityDistrict], buildings: [CityBuilding]) -> CityBounds {
        var minX: Float = 0, maxX: Float = 8, minZ: Float = 0, maxZ: Float = 8
        var first = true
        func include(x: Float, z: Float) {
            if first { minX = x; maxX = x; minZ = z; maxZ = z; first = false }
            else {
                minX = min(minX, x); maxX = max(maxX, x)
                minZ = min(minZ, z); maxZ = max(maxZ, z)
            }
        }
        for d in districts {
            include(x: d.x - d.width / 2, z: d.z - d.depth / 2)
            include(x: d.x + d.width / 2, z: d.z + d.depth / 2)
        }
        for b in buildings { include(x: b.x, z: b.z) }
        return CityBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ)
    }
}
