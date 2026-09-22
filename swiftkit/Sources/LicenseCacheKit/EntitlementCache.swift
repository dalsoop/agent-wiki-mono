import Foundation

/// 자격 판정 결과 캐시 모델.
public struct CachedEntitlementEntry: Codable, Sendable, Equatable {
    public var bundleId: String
    public var status: EntitlementStatus
    public var cachedAt: Date
    public var expiresAt: Date

    public init(
        bundleId: String,
        status: EntitlementStatus,
        cachedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.bundleId = bundleId
        self.status = status
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
    }
}

/// 자격 판정 캐시 저장소 (서버 결과 캐싱).
public struct EntitlementCache: Sendable {
    public static var defaultCacheFileURL: URL {
        if let custom = ProcessInfo.processInfo.environment["GUJO_ENTITLEMENT_CACHE_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("entitlements.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath, isDirectory: true)
        return base.appendingPathComponent("Gujo/cache/entitlements.json")
    }

    public let cacheFileURL: URL
    public let defaultTTL: TimeInterval

    public init(
        cacheFileURL: URL? = nil,
        defaultTTL: TimeInterval = 604800 // 기본 7일 (초 단위)
    ) {
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL
        self.defaultTTL = defaultTTL
    }

    /// 캐시된 자격 상태 조회 (만료되었으면 nil).
    public func get(bundleId: String, now: Date = Date()) -> EntitlementStatus? {
        let entries = loadEntries()
        guard let entry = entries[bundleId] else { return nil }
        if now > entry.expiresAt {
            return nil
        }
        return entry.status
    }

    /// 자격 상태를 캐시에 저장.
    public func set(
        bundleId: String,
        status: EntitlementStatus,
        ttl: TimeInterval? = nil,
        now: Date = Date()
    ) {
        var entries = loadEntries()
        let effectiveTTL = ttl ?? defaultTTL
        let entry = CachedEntitlementEntry(
            bundleId: bundleId,
            status: status,
            cachedAt: now,
            expiresAt: now.addingTimeInterval(effectiveTTL)
        )
        entries[bundleId] = entry
        saveEntries(entries)
    }

    /// 특정 bundleId 캐시 삭제.
    public func remove(bundleId: String) {
        var entries = loadEntries()
        entries.removeValue(forKey: bundleId)
        saveEntries(entries)
    }

    /// 전체 캐시 비우기.
    public func clear() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private func loadEntries() -> [String: CachedEntitlementEntry] {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path),
              let data = try? Data(contentsOf: cacheFileURL) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([String: CachedEntitlementEntry].self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveEntries(_ entries: [String: CachedEntitlementEntry]) {
        let dir = cacheFileURL.deletingLastPathComponent()
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            _ = error // 캐시 저장 실패 시 무시
        }
    }
}
