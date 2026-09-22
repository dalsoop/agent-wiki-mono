import Foundation
import StateRootKit

/// 오프라인 라이선스 캐시. 서버 응답을 디스크에 저장하고 유예 시간 내 재사용.
public struct LicenseCache: Codable, Sendable {
    public let response: LicenseResponse
    public let checkedAt: Date
    public let deviceToken: String

    public init(response: LicenseResponse, checkedAt: Date = Date(), deviceToken: String) {
        self.response = response
        self.checkedAt = checkedAt
        self.deviceToken = deviceToken
    }

    public var isWithinGrace: Bool {
        let graceSeconds = Double(response.offlineGraceHours) * 3600
        return Date().timeIntervalSince(checkedAt) < graceSeconds
    }

    public var effectiveAccessLevel: AccessLevel {
        guard isWithinGrace else { return .readOnly }
        return response.effectiveAccessLevel
    }

    public var needsRefresh: Bool {
        Date().timeIntervalSince(checkedAt) >= Double(response.checkIntervalSeconds)
    }

    // MARK: - Persistence

    static let relativePath = ".license/cache.json"

    public static func load() -> LicenseCache? {
        let url = StateRootKit.url(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseCache.self, from: data)
    }

    public func save() throws {
        let url = StateRootKit.url(LicenseCache.relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
