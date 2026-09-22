import Foundation

/// GUJO Pure Page Specification (PC 1440px SSOT Model)
public struct PageSpec: Codable, Sendable, Identifiable {
    public var id: String { uuid }
    public let uuid: String
    public let tenantUuid: String
    public let shellUuid: String
    public let slugAlias: String
    public let title: String
    public let targetEnvironment: String
    public let purpose: String
    public let archetype: String
    public let blocks: [BlockSpec]
    public let states: [String: StateSpec]
    public let routeContract: RouteContractSpec?
    public let truthAssertions: TruthAssertionsSpec?

    public init(
        uuid: String,
        tenantUuid: String,
        shellUuid: String,
        slugAlias: String,
        title: String,
        targetEnvironment: String = "PC-Desktop-1440",
        purpose: String,
        archetype: String,
        blocks: [BlockSpec] = [],
        states: [String: StateSpec] = [:],
        routeContract: RouteContractSpec? = nil,
        truthAssertions: TruthAssertionsSpec? = nil
    ) {
        self.uuid = uuid
        self.tenantUuid = tenantUuid
        self.shellUuid = shellUuid
        self.slugAlias = slugAlias
        self.title = title
        self.targetEnvironment = targetEnvironment
        self.purpose = purpose
        self.archetype = archetype
        self.blocks = blocks
        self.states = states
        self.routeContract = routeContract
        self.truthAssertions = truthAssertions
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case tenantUuid = "tenant_uuid"
        case shellUuid = "shell_uuid"
        case slugAlias = "slug_alias"
        case title
        case targetEnvironment = "target_environment"
        case purpose
        case archetype
        case blocks
        case states
        case routeContract = "route_contract"
        case truthAssertions = "truth_assertions"
    }
}

public struct BlockSpec: Codable, Sendable, Identifiable {
    public let id: String
    public let primitive: String
    public let title: String?
    public let description: String?
    public let fields: [String: AnyCodableValue]?
    public let items: [ItemSpec]?
    public let actions: [ActionItemSpec]?

    public init(
        id: String,
        primitive: String,
        title: String? = nil,
        description: String? = nil,
        fields: [String: AnyCodableValue]? = nil,
        items: [ItemSpec]? = nil,
        actions: [ActionItemSpec]? = nil
    ) {
        self.id = id
        self.primitive = primitive
        self.title = title
        self.description = description
        self.fields = fields
        self.items = items
        self.actions = actions
    }
}

public struct ItemSpec: Codable, Sendable {
    public let label: String?
    public let hint: String?
    public let selected: Bool?

    public init(label: String? = nil, hint: String? = nil, selected: Bool? = nil) {
        self.label = label
        self.hint = hint
        self.selected = selected
    }
}

public struct ActionItemSpec: Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let primary: Bool?

    public init(id: String, label: String, primary: Bool? = nil) {
        self.id = id
        self.label = label
        self.primary = primary
    }
}

public struct StateSpec: Codable, Sendable {
    public let badge: String?
    public let notice: String?
    public let actions: [String: String]?
    public let recovery: RecoverySpec?

    public init(
        badge: String? = nil,
        notice: String? = nil,
        actions: [String: String]? = nil,
        recovery: RecoverySpec? = nil
    ) {
        self.badge = badge
        self.notice = notice
        self.actions = actions
        self.recovery = recovery
    }
}

public struct RecoverySpec: Codable, Sendable {
    public let label: String?
    public let target: String?
    public let action: String?

    public init(label: String? = nil, target: String? = nil, action: String? = nil) {
        self.label = label
        self.target = target
        self.action = action
    }
}

public struct RouteContractSpec: Codable, Sendable {
    public let inbound: InboundRouteSpec?
    public let outbound: OutboundRouteSpec?

    public init(inbound: InboundRouteSpec? = nil, outbound: OutboundRouteSpec? = nil) {
        self.inbound = inbound
        self.outbound = outbound
    }
}

public struct InboundRouteSpec: Codable, Sendable {
    public let path: String?
    public let carry: [String: String]?

    public init(path: String? = nil, carry: [String: String]? = nil) {
        self.path = path
        self.carry = carry
    }
}

public struct OutboundRouteSpec: Codable, Sendable {
    public let targets: [String]?

    public init(targets: [String]? = nil) {
        self.targets = targets
    }
}

public struct TruthAssertionsSpec: Codable, Sendable {
    public let facts: [String: AnyCodableValue]?

    public init(facts: [String: AnyCodableValue]? = nil) {
        self.facts = facts
    }
}

/// Type-safe Codable representation for dynamic JSON/YAML values
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        do {
            self = .bool(try container.decode(Bool.self))
            return
        } catch {}
        do {
            self = .int(try container.decode(Int.self))
            return
        } catch {}
        do {
            self = .double(try container.decode(Double.self))
            return
        } catch {}
        do {
            self = .string(try container.decode(String.self))
            return
        } catch {}
        do {
            self = .array(try container.decode([AnyCodableValue].self))
            return
        } catch {}
        do {
            self = .dictionary(try container.decode([String: AnyCodableValue].self))
            return
        } catch {}
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}
