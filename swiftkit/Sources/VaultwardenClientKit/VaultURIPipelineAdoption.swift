import Foundation

extension VaultURIPipeline {
    /// 누락된 확장 주소·사이트 태그·원장 버전을 채운다. 대기(빈 URI)·인프라는 건드리지 않는다.
    public static func applyAdoption(_ item: VaultItem) -> VaultItem {
        var next = item
        guard next.isLogin, !next.deleted else { return item }
        if shouldRehomeToNote(next) { return item }
        var uris = sanitizedURIList(next.loginURIs)
        let namedIntranet = uris.contains(where: isNamedIntranetURI)
        if !uris.contains(where: { isPublicWebURI($0) || isAppScheme($0) }),
           !namedIntranet,
           let fill = proposeFromName(next) {
            uris = [fill.uri]
        }
        if uris.contains(where: { isPublicWebURI($0) || isAppScheme($0) }) {
            next.loginURIs = expandedURIList(uris)
        } else if namedIntranet {
            next.loginURIs = uris
        } else {
            return VaultPlacement.apply(item)
        }
        var tags = next.tags
        for host in siteTags(from: next.loginURIs) {
            if !tags.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) {
                tags.append(host)
            }
        }
        next.tags = tags
        let value = "v\(schemaVersion) n=\(next.loginURIs.count)"
        if let index = next.fields.firstIndex(where: { $0.name == ledgerFieldName }) {
            next.fields[index].value = value
            next.fields[index].hidden = false
        } else {
            next.fields.append(VaultField(name: ledgerFieldName, value: value, hidden: false))
        }
        return VaultPlacement.apply(next)
    }

    public static func adoptedIfNeeded(_ item: VaultItem) -> VaultItem? {
        guard item.isLogin, !item.deleted, !shouldRehomeToNote(item) else { return nil }
        if item.needsLoginURI, proposeFromName(item) == nil { return nil }
        let adopted = applyAdoption(item)
        guard adopted != item else { return nil }
        return adopted
    }

    public static func ledgerVersion(of item: VaultItem) -> Int {
        guard let raw = item.fields.first(where: { $0.name == ledgerFieldName })?.value else { return 0 }
        if let match = raw.range(of: #"v(\d+)"#, options: .regularExpression) {
            let digits = raw[match].dropFirst()
            return Int(digits) ?? 0
        }
        return Int(raw.split(separator: " ").first ?? "") ?? 0
    }

    /// 태그 정본 — 로그인 서브도메인이 아니라 사이트 루트만. `www.` 는 안 붙인다.
    public static func siteTags(from uris: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for uri in uris {
            guard isPublicWebURI(uri), let apex = registrableHost(from: uri),
                  seen.insert(apex).inserted else { continue }
            out.append(apex)
            if out.count >= maxAutoURIs { break }
        }
        return out
    }

    /// 앱 스킴·인프라만 남기고, 확장 과정에서 붙은 가짜 https 는 뺀다.
    public static func sanitizedURIList(_ uris: [String]) -> [String] {
        let current = normalizedURIList(uris.joined(separator: "\n"))
        let apps = current.filter(isAppScheme)
        let infra = current.filter(isInfrastructureURI)
        let web = current.filter(isPublicWebURI)
        if !apps.isEmpty { return apps + web }
        if !infra.isEmpty { return infra }
        return web.isEmpty ? current : web
    }
}
