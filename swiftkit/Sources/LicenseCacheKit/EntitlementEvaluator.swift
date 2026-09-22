import Foundation

/// 자격 판정 순서: 서버 → 캐시 → 오프라인 파일 → notConnected
public struct EntitlementEvaluator: Sendable {
    public let store: OfflineLicenseStore
    public let cache: EntitlementCache
    public let now: @Sendable () -> Date

    public init(
        store: OfflineLicenseStore = OfflineLicenseStore(),
        cache: EntitlementCache = EntitlementCache(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.cache = cache
        self.now = now
    }

    /// 자격을 순서에 따라 판정:
    /// 1. 서버 확인 시도 -> 성공 시 캐시 갱신 및 반환
    /// 2. 서버 불능 시 캐시 확인 -> 유효 캐시 시 available 반환
    /// 3. 캐시 부재 시 오프라인 라이선스 파일 확인 -> 유효 서명 시 available 반환
    /// 4. 모두 실패 시 notConnected 반환
    public func evaluate(
        bundleId: String,
        serverCheck: (@Sendable () async throws -> EntitlementStatus)? = nil
    ) async -> EntitlementStatus {
        let currentDate = now()

        // 1. 서버 (Server)
        if let serverCheck {
            do {
                let status = try await serverCheck()
                switch status {
                case .available:
                    cache.set(bundleId: bundleId, status: .available, now: currentDate)
                    return .available
                case .notEntitled:
                    return .notEntitled
                case .notConnected, .unavailable, .authorityMissing:
                    // 서버 불능/미연결 상태 -> 캐시로 진행
                    break
                }
            } catch {
                _ = error // 서버 통신 오류, 타임아웃 등 불능 -> 캐시로 진행
            }
        }

        // 2. 캐시 (Cache)
        if let cached = cache.get(bundleId: bundleId, now: currentDate) {
            if cached == .available {
                return .available
            }
        }

        // 3. 오프라인 파일 (Offline License File)
        if store.hasValidLicense(for: bundleId) {
            return .available
        }

        // 4. notConnected
        return .notConnected
    }
}
