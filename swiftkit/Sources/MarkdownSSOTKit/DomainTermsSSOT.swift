import Foundation

/// 도메인 및 서비스 용어 SSOT 원장 모델.
/// `AlignRuleProvider` 프로토콜을 준수하여 다형적 정렬 엔진에서 바로 활용됩니다.
public struct DomainTermsSSOT: Codable, Sendable, Equatable, AlignRuleProvider {
    public struct Service: Codable, Sendable, Equatable {
        public let canonicalName: String
        public let devDomain: String
        public let localUrl: String
        public let deprecated: [String]
        public let replacements: [String: String]?

        public init(
            canonicalName: String,
            devDomain: String,
            localUrl: String,
            deprecated: [String] = [],
            replacements: [String: String]? = nil
        ) {
            self.canonicalName = canonicalName
            self.devDomain = devDomain
            self.localUrl = localUrl
            self.deprecated = deprecated
            self.replacements = replacements
        }
    }

    public let version: String?
    public let description: String?
    public let services: [String: Service]

    public var ledgerIdentifier: String {
        "DomainTermsSSOT(version: \(version ?? "unknown"), services: \(services.count))"
    }

    public init(
        version: String? = "1.0.0",
        description: String? = nil,
        services: [String: Service]
    ) {
        self.version = version
        self.description = description
        self.services = services
    }

    public static func load(from url: URL) throws -> DomainTermsSSOT {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DomainTermsSSOT.self, from: data)
    }

    public static func load(fromPath path: String) throws -> DomainTermsSSOT {
        try load(from: URL(fileURLWithPath: path))
    }

    public func replacementRules() -> [(from: String, to: String)] {
        allReplacementsSorted()
    }

    /// 원장 `replacements`만 사용한다. 추론 치환은 금지(엔드포인트 하드코딩 재발 방지).
    public func allReplacementsSorted() -> [(from: String, to: String)] {
        var map: [String: String] = [:]
        for service in services.values {
            mergeExplicitReplacements(service.replacements, into: &map)
        }
        return map
            .filter { $0.key != $0.value }
            .map { (from: $0.key, to: $0.value) }
            .sorted { $0.from.count > $1.from.count }
    }

    public func validate() -> [String] {
        guard !services.isEmpty else {
            return ["SSOT 원장에 등록된 서비스가 없습니다."]
        }
        var seenPatterns = Set<String>()
        return services.flatMap { key, service in
            validateService(key: key, service: service, seenPatterns: &seenPatterns)
        }
    }

    private func mergeExplicitReplacements(
        _ replacements: [String: String]?,
        into map: inout [String: String]
    ) {
        guard let replacements else { return }
        for (from, to) in replacements where from != to {
            map[from] = to
        }
    }

    private func validateService(
        key: String,
        service: Service,
        seenPatterns: inout Set<String>
    ) -> [String] {
        var issues: [String] = []
        issues.append(contentsOf: emptyFieldIssues(key: key, service: service))
        issues.append(contentsOf: replacementIssues(
            key: key,
            replacements: service.replacements ?? [:],
            seenPatterns: &seenPatterns
        ))
        issues.append(contentsOf: service.deprecated.compactMap { dep in
            dep.isEmpty ? "[\(key)] deprecated 항목이 비어있습니다." : nil
        })
        return issues
    }

    private func emptyFieldIssues(key: String, service: Service) -> [String] {
        [
            service.canonicalName.isEmpty ? "[\(key)] canonicalName이 비어있습니다." : nil,
            service.devDomain.isEmpty ? "[\(key)] devDomain이 비어있습니다." : nil,
            service.localUrl.isEmpty ? "[\(key)] localUrl이 비어있습니다." : nil,
        ].compactMap { $0 }
    }

    private func replacementIssues(
        key: String,
        replacements: [String: String],
        seenPatterns: inout Set<String>
    ) -> [String] {
        var issues: [String] = []
        for (from, to) in replacements {
            issues.append(contentsOf: issuesForPair(key: key, from: from, to: to, seen: seenPatterns))
            seenPatterns.insert(from)
        }
        return issues
    }

    private func issuesForPair(
        key: String,
        from: String,
        to: String,
        seen: Set<String>
    ) -> [String] {
        [
            from.isEmpty ? "[\(key)] 치환 대상(from)이 비어있습니다." : nil,
            from == to ? "[\(key)] 동일어 치환 규칙 detected: '\(from)' -> '\(to)'" : nil,
            seen.contains(from) ? "[\(key)] 중복 치환 패턴 detected: '\(from)'" : nil,
        ].compactMap { $0 }
    }
}
