import Foundation

/// 금고 항목의 **위치 축**. 폴더(주제)와 다른 정본.
///
/// | 축 | 값 | 의미 |
/// | 망 | 인터넷 / 인트라넷 / 앱 | 공개망 vs 사설망 vs 앱 스킴 |
/// | 운영 | SaaS / 온프레미스 / 앱 | 남이 굴리는 서비스 vs 우리가 굴리는 기계 |
/// | 테넌트 | ranode · 집 · 개인 … | 어느 자리의 자원인지 |
/// | 소유자 | 아이디·브래킷 | 누구 계정인지 |
public enum VaultPlacement {
    public static let netField = "vw.net"
    public static let opsField = "vw.ops"
    public static let tenantField = "vw.tenant"
    public static let ownerField = "vw.owner"

    public static let netPrefix = "망:"
    public static let opsPrefix = "운영:"
    public static let tenantPrefix = "테넌트:"
    public static let ownerPrefix = "소유자:"

    public struct Snapshot: Sendable, Equatable {
        public var network: String
        public var ops: String
        public var tenant: String
        public var owner: String

        public var tags: [String] {
            [
                netPrefix + network,
                opsPrefix + ops,
                tenantPrefix + tenant,
                ownerPrefix + owner,
            ]
        }

        public init(network: String, ops: String, tenant: String, owner: String) {
            self.network = network
            self.ops = ops
            self.tenant = tenant
            self.owner = owner
        }
    }

    public static func isPlacementTag(_ tag: String) -> Bool {
        tag.hasPrefix(netPrefix) || tag.hasPrefix(opsPrefix)
            || tag.hasPrefix(tenantPrefix) || tag.hasPrefix(ownerPrefix)
    }

    /// 사람이 고칠 커스텀 필드가 아니다. 상세·편집에서 숨긴다.
    public static func isMachineField(_ name: String) -> Bool {
        name == netField || name == opsField || name == tenantField || name == ownerField
            || name == VaultURIPipeline.ledgerFieldName
            || name == VaultItem.tagFieldName
    }

    public static func classify(_ item: VaultItem) -> Snapshot {
        let uris = hosts(of: item)
        let apps = uris.contains { VaultURIPipeline.isAppScheme($0) }
        let intranet = uris.contains { VaultURIPipeline.isInfrastructureURI($0) }
        let web = uris.contains { VaultURIPipeline.isPublicWebURI($0) }
        let network: String
        if intranet && !web { network = "인트라넷" }
        else if apps && !web && !intranet { network = "앱" }
        else if web { network = "인터넷" }
        else if intranet { network = "인트라넷" }
        else if item.type == 2 { network = "인트라넷" }
        else { network = "미분류" }

        let ops: String
        if network == "인트라넷" { ops = "온프레미스" }
        else if network == "앱" { ops = "앱" }
        else if network == "인터넷" { ops = "SaaS" }
        else { ops = "미분류" }

        return Snapshot(
            network: network,
            ops: ops,
            tenant: tenant(of: item, uris: uris),
            owner: inferredOwner(of: item)
        )
    }

    public static func apply(_ item: VaultItem) -> VaultItem {
        var next = item
        let snap = classify(item)
        func stamp(_ name: String, _ value: String) {
            if let index = next.fields.firstIndex(where: { $0.name == name }) {
                next.fields[index].value = value
                next.fields[index].hidden = false
            } else {
                next.fields.append(VaultField(name: name, value: value, hidden: false))
            }
        }
        stamp(netField, snap.network)
        stamp(opsField, snap.ops)
        stamp(tenantField, snap.tenant)
        stamp(ownerField, snap.owner)
        var tags = next.tags.filter { !isPlacementTag($0) }
        tags.append(contentsOf: snap.tags)
        next.tags = tags
        return next
    }

    public static func appliedIfNeeded(_ item: VaultItem) -> VaultItem? {
        guard !item.deleted, VaultCipherType.editable.contains(item.type == 0 ? 1 : item.type) else {
            return nil
        }
        let next = apply(item)
        return next == item ? nil : next
    }

    public static func scan(items: [VaultItem]) -> [VaultItem] {
        items.compactMap(appliedIfNeeded)
    }

    // MARK: - 추론

    private static func hosts(of item: VaultItem) -> [String] {
        var uris = item.loginURIs
        if uris.isEmpty {
            for line in item.notes.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("호스트:") {
                    uris.append(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return uris
    }

    private static func tenant(of item: VaultItem, uris: [String]) -> String {
        let blob = (uris + [item.name, item.notes]).joined(separator: " ").lowercased()
        let named: [(needle: String, tenant: String)] = [
            ("ranode", "ranode"),
            ("internal.kr", "ranode"),
            ("dalsoop", "dalsoop"),
            ("presser", "presser"),
            ("wadecho", "wadecho"),
            ("77azit", "azit"),
        ]
        for rule in named where blob.contains(rule.needle) {
            return rule.tenant
        }
        for uri in uris {
            guard let host = VaultURIPipeline.endpointHost(of: uri) else { continue }
            if VaultURIPipeline.isIPv4(host) {
                if host.hasPrefix("192.168.0.") || host.hasPrefix("192.168.1.") { return "집" }
                if host.hasPrefix("192.168.") { return "ranode" }
                if host.hasPrefix("127.") { return "로컬" }
            }
            if host == "localhost" { return "로컬" }
        }
        if item.name.lowercased().contains("공유기") || item.name.contains("원룸") { return "집" }
        if VaultBracketName.parse(item.name).contains(where: { $0 == "인프라" }) { return "ranode" }
        return "개인"
    }

    private static func inferredOwner(of item: VaultItem) -> String {
        let user = item.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { return sanitize(user) }
        let name = item.name
        if let match = name.range(
            of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            options: .regularExpression
        ) {
            return sanitize(String(name[match]))
        }
        if let primary = VaultBracketName.parse(name).first { return sanitize(primary) }
        return "미지정"
    }

    private static func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: ",", with: ".")
        if compact.count <= 40 { return compact.isEmpty ? "미지정" : compact }
        return String(compact.prefix(40))
    }

    // MARK: - 목록 묶기

    public enum BrowseGroup: String, Sendable, CaseIterable {
        case tenant
        case network
        case none
    }

    public struct BrowseSection: Sendable, Equatable, Identifiable {
        public var id: String { title }
        public var title: String
        public var items: [VaultItem]
        public init(title: String, items: [VaultItem]) {
            self.title = title
            self.items = items
        }
    }

    public static func network(of item: VaultItem) -> String {
        item.fields.first { $0.name == netField }?.value ?? classify(item).network
    }

    public static func tenant(of item: VaultItem) -> String {
        item.fields.first { $0.name == tenantField }?.value ?? classify(item).tenant
    }

    public static func owner(of item: VaultItem) -> String {
        item.fields.first { $0.name == ownerField }?.value ?? classify(item).owner
    }

    /// 행 배지 — 인터넷·개인은 생략하고 예외만 보여 목록이 조용해진다.
    public static func browseChips(_ item: VaultItem) -> [String] {
        var chips: [String] = []
        let net = network(of: item)
        if net != "인터넷" && net != "미분류" { chips.append(net) }
        let ten = tenant(of: item)
        if ten != "개인" && ten != "미분류" { chips.append(ten) }
        return chips
    }

    public static func browseSections(_ items: [VaultItem], group: BrowseGroup) -> [BrowseSection] {
        let sorted = items.sorted(by: browseOrder)
        if group == .none {
            return [BrowseSection(title: "", items: sorted)]
        }
        var buckets: [(key: String, items: [VaultItem])] = []
        var index: [String: Int] = [:]
        for item in sorted {
            let key = group == .tenant ? tenant(of: item) : network(of: item)
            if let existing = index[key] {
                buckets[existing].items.append(item)
            } else {
                index[key] = buckets.count
                buckets.append((key, [item]))
            }
        }
        let rank = group == .tenant ? tenantRank : networkRank
        return buckets
            .sorted { lhs, rhs in
                let li = rank.firstIndex(of: lhs.key) ?? rank.count
                let ri = rank.firstIndex(of: rhs.key) ?? rank.count
                if li != ri { return li < ri }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { BrowseSection(title: $0.key, items: $0.items) }
    }

    public static func orderedTagValues(_ counts: [(tag: String, count: Int)], prefix: String) -> [(tag: String, count: Int)] {
        let rank = prefix == netPrefix ? networkRank : prefix == tenantPrefix ? tenantRank : []
        return counts.sorted { lhs, rhs in
            let left = String(lhs.tag.dropFirst(prefix.count))
            let right = String(rhs.tag.dropFirst(prefix.count))
            let li = rank.firstIndex(of: left) ?? rank.count
            let ri = rank.firstIndex(of: right) ?? rank.count
            if li != ri { return li < ri }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private static let networkRank = ["인트라넷", "앱", "인터넷", "미분류"]
    private static let tenantRank = [
        "ranode", "집", "dalsoop", "presser", "wadecho", "azit", "로컬", "개인", "미분류",
    ]

    private static func browseOrder(_ lhs: VaultItem, _ rhs: VaultItem) -> Bool {
        if lhs.favorite != rhs.favorite { return lhs.favorite && !rhs.favorite }
        let left = VaultBracketName.listTitle(from: lhs.name)
        let right = VaultBracketName.listTitle(from: rhs.name)
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }
}
