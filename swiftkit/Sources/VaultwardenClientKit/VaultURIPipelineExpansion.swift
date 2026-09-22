import Foundation

extension VaultURIPipeline {
    public static func expandedURIList(_ uris: [String]) -> [String] {
        let current = sanitizedURIList(uris)
        var out = current
        func append(_ raw: String) {
            let cap = max(maxAutoURIs, current.count)
            guard out.count < cap else { return }
            guard isPublicWebURI(raw) else { return }
            let value = normalizedURI(raw)
            guard !isBlankURI(value) else { return }
            if out.contains(where: { $0.compare(value, options: .caseInsensitive) == .orderedSame }) { return }
            out.append(value)
        }
        for uri in current {
            guard isPublicWebURI(uri) else { continue }
            if let origin = originURI(uri) { append(origin) }
        }
        for uri in current {
            guard isPublicWebURI(uri), let apex = registrableHost(from: uri) else { continue }
            append(apex)
            append("www.\(apex)")
            for extra in relatedHosts[apex] ?? [] { append(extra) }
        }
        return out
    }

    /// 쿼리·경로를 뺀 `https://host`. 홈페이지 매칭용. 원본 URI 는 지우지 않는다.
    public static func originURI(_ uri: String) -> String? {
        guard var components = URLComponents(string: normalizedURI(uri)),
              let host = components.host, !host.isEmpty else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard var value = components.string, !isBlankURI(value) else { return nil }
        if value.hasSuffix("/") { value.removeLast() }
        return value
    }

    public static func expandScan(items: [VaultItem]) -> Snapshot {
        let logins = items.filter { !$0.deleted && $0.isLogin }
        let rows: [Row] = logins.compactMap { item in
            guard let adopted = adoptedIfNeeded(item) else { return nil }
            let added = adopted.loginURIs.filter { candidate in
                !item.loginURIs.contains { $0.compare(candidate, options: .caseInsensitive) == .orderedSame }
            }
            var reasons: [String] = []
            if !added.isEmpty { reasons.append("주소 추가 \(added.joined(separator: ", "))") }
            if ledgerVersion(of: item) < schemaVersion { reasons.append("원장 v\(schemaVersion)") }
            let newTags = Set(adopted.tags).subtracting(item.tags)
            if !newTags.isEmpty { reasons.append("태그 \(newTags.sorted().joined(separator: ", "))") }
            return Row(
                itemID: item.id,
                itemName: item.name,
                proposedURI: adopted.loginURIs.joined(separator: "\n"),
                reason: reasons.isEmpty ? "웹 주소 관리" : reasons.joined(separator: " · ")
            )
        }
        .sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
        return Snapshot(loginCount: logins.count, presentCount: logins.filter { !$0.needsLoginURI }.count, rows: rows)
    }
}
