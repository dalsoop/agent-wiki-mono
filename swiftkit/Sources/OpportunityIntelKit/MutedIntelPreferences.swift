import Foundation

/// 도메인 중립 관심 없음(Mute) 설정 모델
public struct MutedIntelPreferences: Codable, Sendable, Equatable {
    public var mutedProviders: [String]
    public var mutedItemIds: [String]
    public var updatedAt: String

    public init(
        mutedProviders: [String] = [],
        mutedItemIds: [String] = [],
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.mutedProviders = mutedProviders
        self.mutedItemIds = mutedItemIds
        self.updatedAt = updatedAt
    }

    /// 특정 항목이 관심 없음(차단)에 해당하는지 검사
    public func isMuted(item: OpportunityIntelItem) -> Bool {
        if mutedItemIds.contains(item.id) { return true }
        let prov = item.provider.lowercased()
        let canon = item.canonical.lowercased()
        return mutedProviders.contains { target in
            let t = target.lowercased()
            return prov.contains(t) || canon == t
        }
    }
}

/// MutedIntelPreferences 영속화 스토어
public enum MutedIntelPreferencesStore {
    public static func load(from url: URL) -> MutedIntelPreferences {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(MutedIntelPreferences.self, from: data) else {
            return MutedIntelPreferences()
        }
        return prefs
    }

    public static func save(_ preferences: MutedIntelPreferences, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(preferences).write(to: url, options: .atomic)
    }

    @discardableResult
    public static func muteProvider(_ provider: String, in url: URL) throws -> MutedIntelPreferences {
        var prefs = load(from: url)
        let clean = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return prefs }
        if !prefs.mutedProviders.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            prefs.mutedProviders.append(clean)
            prefs.updatedAt = ISO8601DateFormatter().string(from: Date())
            try save(prefs, to: url)
        }
        return prefs
    }

    @discardableResult
    public static func unmuteProvider(_ provider: String, in url: URL) throws -> MutedIntelPreferences {
        var prefs = load(from: url)
        let clean = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.mutedProviders.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        prefs.updatedAt = ISO8601DateFormatter().string(from: Date())
        try save(prefs, to: url)
        return prefs
    }
}
