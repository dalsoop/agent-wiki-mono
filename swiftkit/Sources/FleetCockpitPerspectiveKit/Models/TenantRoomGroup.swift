import Foundation

/// 테넌트 식별 및 렌더링 메타데이터
public struct TenantContext: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: String { logicalID }
    public let slug: String
    public let logicalID: String
    public let name: String
    public let symbol: String
    public let colorHex: String

    public init(
        slug: String,
        name: String? = nil,
        symbol: String? = nil,
        colorHex: String? = nil
    ) {
        var clean = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("tenant:") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("tenant-") {
            clean = String(clean.dropFirst(7))
        }
        let normalizedSlug = clean.isEmpty ? "default" : clean.lowercased()
        self.slug = normalizedSlug
        self.logicalID = "tenant:\(normalizedSlug)"

        if let name, !name.isEmpty {
            self.name = name
        } else {
            self.name = normalizedSlug.capitalized
        }

        switch normalizedSlug {
        case "personal":
            self.symbol = symbol ?? "person.fill"
            self.colorHex = colorHex ?? "#5E5CE6"
        case "gujo":
            self.symbol = symbol ?? "globe.asia.australia"
            self.colorHex = colorHex ?? "#30D158"
        case "business":
            self.symbol = symbol ?? "briefcase.fill"
            self.colorHex = colorHex ?? "#FF9F0A"
        case "dev-ops":
            self.symbol = symbol ?? "wrench.and.screwdriver.fill"
            self.colorHex = colorHex ?? "#FF453A"
        case "system":
            self.symbol = symbol ?? "gearshape.2.fill"
            self.colorHex = colorHex ?? "#8E8E93"
        default:
            self.symbol = symbol ?? "square.grid.2x2"
            self.colorHex = colorHex ?? "#64D2FF"
        }
    }

    public static let `default` = TenantContext(slug: "default")
    public static let personal = TenantContext(slug: "personal")
    public static let gujo = TenantContext(slug: "gujo")
}

/// 테넌트별 방 묶음 및 하위 리소스 DTO
public struct TenantRoomGroup: Sendable, Equatable, Identifiable {
    public var id: String { tenant.id }
    public let tenant: TenantContext
    public var rooms: [ActiveRoomEntry]
    public var barItems: [UnifiedBarItem]

    public init(
        tenant: TenantContext,
        rooms: [ActiveRoomEntry] = [],
        barItems: [UnifiedBarItem] = []
    ) {
        self.tenant = tenant
        self.rooms = rooms
        self.barItems = barItems
    }

    public var activeOccupantCount: Int {
        rooms.filter(\.isOccupied).count
    }

    public var runningJobCount: Int {
        barItems.reduce(0) { $0 + $1.runningSubjobCount }
    }
}
