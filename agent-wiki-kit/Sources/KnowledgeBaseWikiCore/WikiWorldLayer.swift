import Foundation
import StateRootKit

/// 위키 world 3층(+기타). GUI·CLI 가 같은 판정을 쓴다.
///
/// `gujo-wiki` 는 git 저장소여도 **원격 공유**이지 코드 repo 원장이 아니다.
/// `person-*` / `~/.tenants/<slug>/wiki` 는 **이 Mac 1인칭**이지 GitLab 441 이 아니다.
public enum WikiWorldLayer: String, Codable, Sendable, CaseIterable, Identifiable {
    case localPerson
    case tenant
    case remoteShared
    case repository
    case other

    public var id: String { rawValue }

    public var groupTitle: String {
        switch self {
        case .localPerson: "로컬 1인칭"
        case .tenant: "테넌트 위키"
        case .remoteShared: "원격 공유 위키"
        case .repository: "이 저장소"
        case .other: "기타 원장"
        }
    }

    public var badge: String {
        switch self {
        case .localPerson: "로컬"
        case .tenant: "테넌트"
        case .remoteShared: "원격"
        case .repository: "저장소"
        case .other: "기타"
        }
    }

    public var systemImage: String {
        switch self {
        case .localPerson: "person.crop.circle"
        case .tenant: "building.2"
        case .remoteShared: "icloud"
        case .repository: "shippingbox"
        case .other: "folder"
        }
    }

    public var sortIndex: Int {
        switch self {
        case .localPerson: 0
        case .tenant: 1
        case .remoteShared: 2
        case .repository: 3
        case .other: 4
        }
    }
}

public struct WikiWorldListItem: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var rootPath: String
    public var layer: WikiWorldLayer
    public var title: String
    public var subtitle: String
    public var selected: Bool
    /// 사람용 표시 이름 — 등록에 없으면 slug(name). 구버전 JSON 은 키가 없어 nil.
    public var display: String?
    /// 사람용 표시 이름(정본 필드).
    public var displayName: String

    public var id: String { name }

    public init(
        name: String,
        rootPath: String,
        layer: WikiWorldLayer,
        title: String,
        subtitle: String,
        selected: Bool,
        display: String? = nil,
        displayName: String? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.layer = layer
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        let resolved = displayName ?? display ?? WorldDisplayNameMapper.defaultDisplayName(for: name)
        self.display = display ?? resolved
        self.displayName = resolved
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.rootPath = try c.decode(String.self, forKey: .rootPath)
        self.layer = try c.decode(WikiWorldLayer.self, forKey: .layer)
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

/// 공유 위키를 **브라우저에서 여는** 주소.
/// git SSH 호스트(`gitlab-ssh…`)와 같지 않다. 전송로 선택은 `gitlab-manager endpoint`.
public enum GujoWikiWeb {
    public static let projectHost = "gitlab.ranode.net"
    public static var projectURL: String {
        "https://\(projectHost)/workspace/contents/gujo-wiki"
    }
    public static var gitHTTPS: String {
        "https://\(projectHost)/workspace/contents/gujo-wiki.git"
    }
}

public enum WikiWorldPresentation: Sendable {
    public static func classify(name: String, rootPath: String) -> WikiWorldLayer {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
            .standardizedFileURL.path
        if trimmed.lowercased() == "gujo-wiki" || path.hasSuffix("/gujo-wiki") {
            return .remoteShared
        }
        if trimmed.lowercased().hasPrefix("person-") {
            return .localPerson
        }
        if path.contains("/.tenants/"), path.hasSuffix("/wiki") {
            return .localPerson
        }
        if path.hasSuffix("/.wiki") || path.contains("/.wiki/") {
            return .repository
        }
        return .other
    }

    public static func inferredPersonWorld(
        tenantID: String? = ProcessInfo.processInfo.environment["TENANT_ID"],
        contextURL: URL = URL(
            fileURLWithPath: StateRootKit.hostPath(
                ".agent-tenant-isolation-manager/current-context.json"))
    ) -> String {
        if let slug = slug(fromTenantID: tenantID), !slug.isEmpty {
            return "person-\(slug)"
        }
        do {
            let data = try Data(contentsOf: contextURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["tenantID"] as? String,
                  let slug = slug(fromTenantID: id)
            else { return "person-personal" }
            return "person-\(slug)"
        } catch {
            return "person-personal"
        }
    }

    public static func slug(fromTenantID raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("tenant:") {
            let slug = String(raw.dropFirst("tenant:".count))
            return slug.isEmpty ? nil : slug
        }
        return raw
    }

    public static func tenantSlug(worldName: String) -> String? {
        let lower = worldName.lowercased()
        guard lower.hasPrefix("person-") else { return nil }
        let slug = String(worldName.dropFirst("person-".count))
        return slug.isEmpty ? nil : slug
    }

    public static func tenantDisplayName(slug: String) -> String {
        switch slug {
        case "personal": "본인"
        case "family": "가족"
        case "silneobal": "실너발"
        case "yun-jeonghan": "윤정한"
        default: slug
        }
    }

    public static func title(name: String, rootPath: String) -> String {
        switch classify(name: name, rootPath: rootPath) {
        case .localPerson:
            let slug = tenantSlug(worldName: name) ?? tenantSlugFromPath(rootPath) ?? name
            return "\(tenantDisplayName(slug: slug)) · 로컬 1인칭"
        case .tenant:
            return "\(name) · 테넌트"
        case .remoteShared:
            return "공유 위키 · 원격"
        case .repository:
            return name
        case .other:
            return name
        }
    }

    public static func subtitle(name: String, rootPath: String) -> String {
        let path = (rootPath as NSString).abbreviatingWithTildeInPath
        switch classify(name: name, rootPath: rootPath) {
        case .localPerson:
            return "이 Mac만 · GitLab 441에 안 올라감 · \(path)"
        case .tenant:
            return "공유 위키 하위 · \(path)"
        case .remoteShared:
            return "\(GujoWikiWeb.projectURL) · \(path)"
        case .repository:
            return "이 repo의 .wiki · \(path)"
        case .other:
            return path
        }
    }

    public static func listItems(
        worlds: [LedgerWorld],
        selectedName: String?
    ) -> [WikiWorldListItem] {
        worlds.map { world in
            let layer = classify(name: world.name, rootPath: world.rootPath)
            let resolvedDisplay = world.display ?? WorldDisplayNameMapper.defaultDisplayName(for: world.name)
            return WikiWorldListItem(
                name: world.name,
                rootPath: world.rootPath,
                layer: layer,
                title: title(name: world.name, rootPath: world.rootPath),
                subtitle: subtitle(name: world.name, rootPath: world.rootPath),
                selected: world.name == selectedName,
                display: resolvedDisplay,
                displayName: resolvedDisplay
            )
        }
        .sorted {
            if $0.layer.sortIndex != $1.layer.sortIndex {
                return $0.layer.sortIndex < $1.layer.sortIndex
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public static func plainText(items: [WikiWorldListItem]) -> String {
        var lines: [String] = []
        for layer in WikiWorldLayer.allCases {
            let rows = items.filter { $0.layer == layer }
            guard !rows.isEmpty else { continue }
            lines.append(layer.groupTitle)
            for row in rows {
                let mark = row.selected ? "*" : " "
                // display 는 뒤에 덧붙인다 — slug 와 같으면(기본값) 기존 포맷 그대로.
                let display = row.display.flatMap { $0 == row.name ? nil : "  display=\($0)" } ?? ""
                lines.append("\(mark) \(row.title)  [\(row.name)]  \(row.rootPath)\(display)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func tenantSlugFromPath(_ rootPath: String) -> String? {
        let parts = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath).pathComponents
        guard let tenants = parts.firstIndex(of: ".tenants"), tenants + 1 < parts.count else {
            return nil
        }
        return parts[tenants + 1]
    }
}
