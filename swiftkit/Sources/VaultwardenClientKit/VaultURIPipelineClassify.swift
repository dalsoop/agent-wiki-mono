import Foundation

extension VaultURIPipeline {
    public static func isAppScheme(_ uri: String) -> Bool {
        let lower = uri.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("androidapp://") || lower.hasPrefix("iosapp://")
    }

    public static func isPublicWebURI(_ uri: String) -> Bool {
        guard !isAppScheme(uri), !isInfrastructureURI(uri), !isBlankURI(uri) else { return false }
        guard let host = endpointHost(of: uri) else { return false }
        let labels = host.split(separator: ".").map { String($0).lowercased() }
        guard labels.count >= 2 else { return false }
        let tld = labels[labels.count - 1]
        let publicTLD: Set<String> = [
            "com", "net", "org", "io", "ai", "app", "dev", "gg", "me", "kr", "co",
            "uk", "jp", "au", "tw", "hk", "cn", "br", "info", "xyz", "shop", "tv",
        ]
        return publicTLD.contains(tld)
    }

    public static func isInfrastructureURI(_ uri: String) -> Bool {
        if isAppScheme(uri) { return false }
        guard let host = endpointHost(of: uri) else {
            return !uri.contains("://") && !uri.contains(".")
        }
        if host == "localhost" || host.hasSuffix(".local") || host.contains(".local.") { return true }
        if host == "internal.kr" || host.hasSuffix(".internal.kr") || host.contains(".internal.") { return true }
        return isIPv4(host)
    }

    /// SSH·순수 IP·localhost 만 메모로 옮긴다. Portainer 같은 이름 있는 인트라넷 웹 UI 는 로그인으로 남긴다.
    public static func shouldRehomeToNote(_ item: VaultItem) -> Bool {
        guard item.isLogin, !item.deleted else { return false }
        let uris = sanitizedURIList(item.loginURIs)
        if uris.contains(where: isAppScheme) { return false }
        if uris.isEmpty { return false }
        if uris.contains(where: isNamedIntranetURI) { return false }
        if uris.contains(where: isPublicWebURI) { return false }
        let name = item.name.lowercased()
        if name.contains("ssh") { return true }
        return uris.allSatisfy { uri in
            guard let host = endpointHost(of: uri) else { return true }
            return isIPv4(host) || host == "localhost"
        }
    }

    /// DNS 이름이 있는 사설 호스트. `portainer.local.ranode.net`, `synology.internal.kr`.
    public static func isNamedIntranetURI(_ uri: String) -> Bool {
        guard isInfrastructureURI(uri), let host = endpointHost(of: uri) else { return false }
        if host == "localhost" || isIPv4(host) { return false }
        return host.contains(where: \.isLetter)
    }

    public static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }

    public static func endpointHost(of uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: withScheme)?.host?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
            !host.isEmpty else { return nil }
        return host
    }

    public static func host(of uri: String) -> String? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: withScheme)?.host?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
            !host.isEmpty else { return nil }
        if host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return nil }
        return host
    }

    /// eTLD+1. `nid.naver.com` → `naver.com`, `juso.go.kr` → `juso.go.kr`.
    public static func registrableHost(from uri: String) -> String? {
        guard let host = host(of: uri) else { return nil }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        let last2 = labels.suffix(2).joined(separator: ".")
        let compound: Set<String> = [
            "co.kr", "or.kr", "go.kr", "ac.kr", "ne.kr", "re.kr", "pe.kr",
            "co.uk", "org.uk", "ac.uk", "gov.uk",
            "com.au", "net.au", "org.au",
            "co.jp", "or.jp", "ne.jp", "ac.jp",
            "com.tw", "com.hk", "com.cn", "com.br",
        ]
        if labels.count >= 3, compound.contains(last2) {
            return labels.suffix(3).joined(separator: ".")
        }
        return last2
    }
}
