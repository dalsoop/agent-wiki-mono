import Foundation

/// 서버 라이선스 체크 API 호출 + 캐시 통합 클라이언트.
public actor LicenseClient {
    private var cached: LicenseCache?
    private let deviceToken: String
    private let serverClient: LicenseServerClient

    public init(deviceToken: String) {
        self.deviceToken = deviceToken
        self.cached = LicenseCache.load()
        self.serverClient = LicenseServerClient(deviceToken: deviceToken)
    }

    /// 현재 접근 수준. 캐시가 유예 내면 캐시, 아니면 서버 체크.
    public func accessLevel() async -> AccessLevel {
        if let cached, !cached.needsRefresh {
            return cached.effectiveAccessLevel
        }
        do {
            let response = try await serverClient.fetch()
            let cache = LicenseCache(response: response, deviceToken: deviceToken)
            try? cache.save()
            self.cached = cache
            return response.effectiveAccessLevel
        } catch {
            if let cached, cached.isWithinGrace {
                return cached.effectiveAccessLevel
            }
            return .readOnly
        }
    }

    /// 서버에 강제 체크(앱 시작 시).
    public func forceCheck() async -> AccessLevel {
        do {
            let response = try await serverClient.fetch()
            let cache = LicenseCache(response: response, deviceToken: deviceToken)
            try? cache.save()
            self.cached = cache
            return response.effectiveAccessLevel
        } catch {
            if let cached, cached.isWithinGrace {
                return cached.effectiveAccessLevel
            }
            return .readOnly
        }
    }

    /// 캐시만으로 즉시 판정(네트워크 없이).
    public func cachedAccessLevel() -> AccessLevel {
        guard let cached else { return .blocked }
        return cached.effectiveAccessLevel
    }
}
