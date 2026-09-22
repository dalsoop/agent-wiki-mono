import Foundation

public enum CityUsage: String, Sendable, Equatable {
    case live
    case used
    case unused
}

public enum CityFilter: String, Sendable, CaseIterable {
    case all
    case used
    case unused
}

public enum CityFace: String, Sendable, Equatable {
    case backend
    case frontend
}

/// Shared vocabulary so apps do not invent role strings.
public enum CityRole: String, Sendable, CaseIterable, Equatable {
    case route
    case controller
    case action
    case query
    case service
    case dto
    case model
    case enumeration
    case job
    case support
    case page
    case component
    case runtime
    case view
    case migration
    case test
}

/// Why a lot is used or unused. Apps map this to copy; they do not invent tokens.
public enum CityReason: String, Sendable, Equatable {
    case livePath
    case reachable
    case rendered
    case imported
    case orphan
    case unsurfaced
    case unrouted
    case missing
}

public enum CityIdentity {
    public static func make(_ role: CityRole, _ name: String) -> String {
        "\(role.rawValue):\(name)"
    }

    public static func folder(of path: String, fallback: String) -> String {
        guard let slash = path.firstIndex(of: "/") else { return fallback }
        let head = String(path[..<slash])
        return head.isEmpty ? fallback : head
    }

    public static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// Input node. District is the package/module; usage stays on the same lot.
public struct CityItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var district: String
    public var role: CityRole
    public var face: CityFace
    public var file: String?
    public var line: Int?
    public var weight: Int
    public var used: Bool
    public var reason: CityReason

    public struct Placement: Sendable, Equatable {
        public var file: String?
        public var line: Int?
        public var weight: Int

        public init(file: String? = nil, line: Int? = nil, weight: Int = 20) {
            self.file = file
            self.line = line
            self.weight = weight
        }
    }

    public init(
        id: String,
        label: String,
        district: String,
        role: CityRole,
        face: CityFace,
        placement: Placement = Placement(),
        used: Bool,
        reason: CityReason
    ) {
        self.id = id
        self.label = label
        self.district = district
        self.role = role
        self.face = face
        self.file = placement.file
        self.line = placement.line
        self.weight = placement.weight
        self.used = used
        self.reason = reason
    }

    public init(
        role: CityRole,
        name: String,
        district: String,
        face: CityFace,
        placement: Placement = Placement(),
        used: Bool,
        reason: CityReason
    ) {
        self.init(
            id: CityIdentity.make(role, name),
            label: name,
            district: district,
            role: role,
            face: face,
            placement: placement,
            used: used,
            reason: reason
        )
    }

    /// `file`·`weight` 를 최상위로 넘기던 호출부용. 값은 `placement` 로만 저장한다.
    @_disfavoredOverload
    public init(
        id: String,
        label: String,
        district: String,
        role: CityRole,
        face: CityFace,
        file: String? = nil,
        line: Int? = nil,
        weight: Int = 20,
        used: Bool,
        reason: CityReason
    ) {
        self.init(
            id: id,
            label: label,
            district: district,
            role: role,
            face: face,
            placement: Placement(file: file, line: line, weight: weight),
            used: used,
            reason: reason
        )
    }
}

public struct CityEdge: Sendable, Equatable {
    public var from: String
    public var to: String
    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public func resolving(_ aliases: [String: String]) -> CityEdge {
        CityEdge(from: aliases[from] ?? from, to: aliases[to] ?? to)
    }
}

public struct CityBuilding: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var district: String
    public var role: CityRole
    public var face: CityFace
    public var file: String?
    public var line: Int?
    public var x: Float
    public var y: Float
    public var z: Float
    public var width: Float
    public var height: Float
    public var depth: Float
    public var usage: CityUsage
    public var reason: CityReason

    public var onFlow: Bool { usage == .live }

    public struct Identity: Sendable, Equatable {
        public var id: String
        public var label: String
        public var district: String
        public var role: CityRole
        public var face: CityFace

        public init(
            id: String,
            label: String,
            district: String,
            role: CityRole,
            face: CityFace
        ) {
            self.id = id
            self.label = label
            self.district = district
            self.role = role
            self.face = face
        }
    }

    public struct Source: Sendable, Equatable {
        public var file: String?
        public var line: Int?

        public init(file: String? = nil, line: Int? = nil) {
            self.file = file
            self.line = line
        }
    }

    public struct Box: Sendable, Equatable {
        public var x: Float
        public var y: Float
        public var z: Float
        public var width: Float
        public var height: Float
        public var depth: Float

        public init(x: Float, y: Float, z: Float, width: Float, height: Float, depth: Float) {
            self.x = x
            self.y = y
            self.z = z
            self.width = width
            self.height = height
            self.depth = depth
        }
    }

    public init(
        identity: Identity,
        source: Source = Source(),
        box: Box,
        usage: CityUsage,
        reason: CityReason
    ) {
        self.id = identity.id
        self.label = identity.label
        self.district = identity.district
        self.role = identity.role
        self.face = identity.face
        self.file = source.file
        self.line = source.line
        self.x = box.x
        self.y = box.y
        self.z = box.z
        self.width = box.width
        self.height = box.height
        self.depth = box.depth
        self.usage = usage
        self.reason = reason
    }
}

public struct CityDistrict: Sendable, Equatable {
    public var name: String
    public var x: Float
    public var z: Float
    public var width: Float
    public var depth: Float

    public init(name: String, x: Float, z: Float, width: Float, depth: Float) {
        self.name = name
        self.x = x
        self.z = z
        self.width = width
        self.depth = depth
    }
}

public struct CityPoint: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    public init(x: Float, y: Float, z: Float) {
        self.x = x; self.y = y; self.z = z
    }
}

public struct CityBounds: Sendable, Equatable {
    public var minX: Float
    public var maxX: Float
    public var minZ: Float
    public var maxZ: Float
    public var centerX: Float { (minX + maxX) / 2 }
    public var centerZ: Float { (minZ + maxZ) / 2 }
    public var span: Float { max(maxX - minX, maxZ - minZ, 8) }
}

public struct CityWorld: Sendable, Equatable {
    public var districts: [CityDistrict]
    public var buildings: [CityBuilding]
    public var segments: [CityEdge]
    public var particlePaths: [[CityPoint]]
    public var bounds: CityBounds
    public var usedCount: Int
    public var unusedCount: Int
    public var uses: [String: [String]]
    public var usedBy: [String: [String]]
    public var labelIds: Set<String>

    public var buildingById: [String: CityBuilding] {
        Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
    }
}

public enum CityReasonPolicy {
    public static func unused(for role: CityRole) -> CityReason {
        switch role {
        case .page, .view, .component: return .orphan
        case .model: return .unsurfaced
        case .controller, .route: return .unrouted
        default: return .unsurfaced
        }
    }

    public static func used(for role: CityRole) -> CityReason {
        switch role {
        case .page: return .rendered
        case .component: return .imported
        default: return .reachable
        }
    }
}
