import Foundation
import RoomPlacementKit
import StateRootKit

/// 타입 안전한 테넌트 식별자 (논리 식별자 "tenant:<slug>"와 물리 slug 간 상호 변환 보장)
public struct TenantID: Sendable, Codable, Equatable, Hashable, CustomStringConvertible, RawRepresentable {
    public let slug: String

    public var rawValue: String { logicalID }

    public var logicalID: String { "tenant:\(slug)" }
    public var description: String { logicalID }

    public init(rawValue: String) {
        self.init(rawValue)
    }

    public init(_ raw: String) {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("tenant:") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("tenant-") {
            clean = String(clean.dropFirst(7))
        }
        if clean.hasPrefix("@") {
            clean = String(clean.dropFirst())
        }
        self.slug = clean.isEmpty ? "default" : clean.lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(logicalID)
    }

    public static let `default` = TenantID("default")
    public static let personal = TenantID("personal")
    public static let gujo = TenantID("gujo")
    public static let business = TenantID("business")
    public static let devOps = TenantID("dev-ops")
    public static let system = TenantID("system")
}

/// 테넌트 일급 시민 도메인 객체 (정본 메타데이터 및 정책)
public struct TenantDomain: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: TenantID { tenantID }
    public let tenantID: TenantID
    public let name: String
    public let symbol: String
    public let colorHex: String
    public let appPrefixes: [String]
    public let rootDirectory: URL

    public init(
        tenantID: TenantID,
        name: String,
        symbol: String,
        colorHex: String,
        appPrefixes: [String] = [],
        rootDirectory: URL? = nil
    ) {
        self.tenantID = tenantID
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.appPrefixes = appPrefixes
        self.rootDirectory = rootDirectory ?? RoomPaths.tenantStateRoot(tenant: tenantID.slug)
    }
}

/// 단일 진실의 원천 테넌트 레지스트리 (디스크 ~/.tenants/ 및 ~/.agent-work-todo/ 연계 지원)
public final class TenantRegistry: Sendable {
    public static let shared = TenantRegistry()

    public static let builtinTenants: [TenantDomain] = [
        TenantDomain(tenantID: .personal, name: "Personal", symbol: "person.fill", colorHex: "#5E5CE6", appPrefixes: ["agent-"]),
        TenantDomain(tenantID: .gujo, name: "Gujo", symbol: "globe.asia.australia", colorHex: "#30D158", appPrefixes: ["gujo-"]),
        TenantDomain(tenantID: .business, name: "Business", symbol: "briefcase.fill", colorHex: "#FF9F0A", appPrefixes: ["business-"]),
        TenantDomain(tenantID: .devOps, name: "Dev & Ops", symbol: "wrench.and.screwdriver.fill", colorHex: "#FF453A", appPrefixes: [
            "build-", "code-", "mac-", "swift-app-", "android-", "ios-", "gpu-", "linux-", "docker-", "container-"
        ]),
        TenantDomain(tenantID: .system, name: "System", symbol: "gearshape.2.fill", colorHex: "#8E8E93", appPrefixes: ["system-"]),
        TenantDomain(tenantID: .default, name: "Default", symbol: "square.grid.2x2", colorHex: "#64D2FF", appPrefixes: [])
    ]

    public init() {}

    /// 물리 `~/.tenants/<slug>` 디렉터리 동적 스캔과 Builtin을 융합한 전체 테넌트 목록
    public func allTenants() -> [TenantDomain] {
        var map: [TenantID: TenantDomain] = [:]
        for b in Self.builtinTenants {
            map[b.tenantID] = b
        }

        let root = RoomPaths.tenantsRoot()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for dir in contents where dir.lastPathComponent != RoomPaths.baseBinName {
                let tid = TenantID(dir.lastPathComponent)
                if map[tid] == nil {
                    map[tid] = TenantDomain(
                        tenantID: tid,
                        name: tid.slug.capitalized,
                        symbol: "folder.badge.gearshape",
                        colorHex: "#A2845E",
                        rootDirectory: dir
                    )
                }
            }
        } catch {
            // 루트 디렉터리가 아직 없거나 접근 불가한 경우 내장 테넌트만 유지
            _ = "\(error)"
        }
        return Array(map.values).sorted { $0.tenantID.slug < $1.tenantID.slug }
    }

    public func resolve(id: TenantID) -> TenantDomain {
        allTenants().first { $0.tenantID == id } ?? TenantDomain(
            tenantID: id,
            name: id.slug.capitalized,
            symbol: "questionmark.folder",
            colorHex: "#8E8E93"
        )
    }

    public func resolve(rawID: String) -> TenantDomain {
        resolve(id: TenantID(rawID))
    }

    public func resolve(bundleID: String) -> TenantDomain {
        var clean = bundleID
        if clean.hasPrefix("net.ranode.") {
            clean = String(clean.dropFirst(11))
        } else if clean.hasPrefix("com.dalsoop.") {
            clean = String(clean.dropFirst(12))
        }
        for t in allTenants() {
            if t.appPrefixes.contains(where: { clean.hasPrefix($0) }) {
                return t
            }
        }
        return resolve(id: .default)
    }
}
