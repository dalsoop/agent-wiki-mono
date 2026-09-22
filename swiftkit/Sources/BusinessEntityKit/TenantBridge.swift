import Foundation
import os
import StateRootKit

/// `~/.business-entity/entities.json` 읽기 전용. 쓰기는 business-entity 앱이 소유한다.
///
/// 호출 API: `StateRootKit.url(".business-entity/entities.json")` + `activeSlug`.
/// 프로필·업태 매핑은 소비 앱에 둔다.
public enum TenantBridge {
    public static let relativePath = ".business-entity/entities.json"
    public static let fallbackSlug = "default"

    private static let entitiesURLOverrideLock = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// 테스트 격리용.
    public static var entitiesURLOverride: URL? {
        get { entitiesURLOverrideLock.withLock { $0 } }
        set { entitiesURLOverrideLock.withLock { $0 = newValue } }
    }

    public static var entitiesURL: URL {
        if let entitiesURLOverride { return entitiesURLOverride }
        return StateRootKit.url(relativePath)
    }

    public enum Source: String, Sendable {
        case override
        case businessEntity = "business-entity"
        case fallback
    }

    public struct Resolution: Sendable {
        public var slug: String
        public var source: Source
    }

    /// `--tenant` 명시가 있으면 그대로 쓴다. 없으면 원장의 활성 slug, 그마저 없으면 fallback.
    public static func resolve(explicit: String? = nil, fileURL: URL? = nil) -> Resolution {
        if let explicit, !explicit.isEmpty {
            return Resolution(slug: explicit, source: .override)
        }
        if let slug = activeSlug(from: fileURL ?? entitiesURL) {
            return Resolution(slug: slug, source: .businessEntity)
        }
        return Resolution(slug: fallbackSlug, source: .fallback)
    }

    public static func activeSlug(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            root = obj
        } catch {
            return nil
        }
        guard let list = root["entities"] as? [[String: Any]] else { return nil }

        if let active = root["activeSlug"] as? String,
           list.contains(where: { ($0["slug"] as? String) == active }) {
            return active
        }
        return list.first(where: { ($0["archived"] as? Bool) != true })
            .flatMap { $0["slug"] as? String }
    }
}
