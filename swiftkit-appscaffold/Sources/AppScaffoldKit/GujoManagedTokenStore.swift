#if GujoManaged
import EndpointRouterKit
import Foundation
import GujoCoreKit

public enum GujoManagedTokenStore {
    public static let tokenCacheKey = "gujo.managed.signedToken"
    public static let cacheKey = "gujo.managed.lastKnownStatus"
    public static let cacheTimeKey = "gujo.managed.lastKnownStatusAt"
    public static let freshWindow: TimeInterval = 6 * 60 * 60

    public static func tokenKey(for bundleID: String?) -> String {
        guard let bid = bundleID else { return tokenCacheKey }
        return tokenCacheKey + "." + bid
    }

    public static func storeToken(_ token: SignedEntitlementToken, bundleID: String? = nil) {
        do {
            let encoded = try token.encodeToken()
            let primaryKey = tokenCacheKey
            UserDefaults.standard.set(encoded, forKey: primaryKey)
            if let bid = bundleID {
                let scopedKey = tokenKey(for: bid)
                UserDefaults.standard.set(encoded, forKey: scopedKey)
            }
        } catch {
            let primaryKey = tokenCacheKey
            UserDefaults.standard.removeObject(forKey: primaryKey)
        }
    }

    public static func parseToken(_ raw: String) -> SignedEntitlementToken? {
        do {
            return try SignedEntitlementToken.parse(raw)
        } catch {
            return nil
        }
    }

    public static func parseAndValidate(
        rawToken: String?,
        now: Date,
        bundleID: String,
        publicKey: String
    ) -> SignedEntitlementToken? {
        guard let raw = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let token = parseToken(raw),
              token.isValid(at: now, expectedBundleID: bundleID, publicKey: publicKey) else {
            return nil
        }
        return token
    }

    public static func loadStoredToken(
        bundleID: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SignedEntitlementToken? {
        if let rawEnv = environment["GUJO_ENTITLEMENT_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawEnv.isEmpty,
           let token = parseToken(rawEnv) {
            return token
        }
        if let bid = bundleID {
            let scopedKey = tokenKey(for: bid)
            if let raw = UserDefaults.standard.string(forKey: scopedKey),
               let token = parseToken(raw) {
                return token
            }
        }
        let primaryKey = tokenCacheKey
        if let raw = UserDefaults.standard.string(forKey: primaryKey),
           let token = parseToken(raw) {
            return token
        }
        return nil
    }

    public static func lastKnown(
        bundleID: String?,
        at date: Date = Date(),
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> GujoManagedStatus? {
        guard let token = loadStoredToken(bundleID: bundleID) else {
            return nil
        }
        return token.effectiveStatus(at: date, expectedBundleID: bundleID, publicKey: publicKey)
    }

    public static func freshAvailableCache(
        bundleID: String? = nil,
        at now: Date = Date(),
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> GujoManagedStatus? {
        if let token = loadStoredToken(bundleID: bundleID),
           token.isValid(at: now, expectedBundleID: bundleID, publicKey: publicKey) {
            return token.status
        }
        guard lastKnown(bundleID: bundleID, at: now, publicKey: publicKey) == .available else { return nil }
        let timeKey = cacheTimeKey
        let at = UserDefaults.standard.double(forKey: timeKey)
        guard at > 0, now.timeIntervalSince1970 - at < freshWindow else { return nil }
        return .available
    }

    @discardableResult
    public static func remember(_ s: GujoManagedStatus) -> GujoManagedStatus {
        let statusKey = cacheKey
        let timeKey = cacheTimeKey
        UserDefaults.standard.set(GujoManaged.encode(s), forKey: statusKey)
        if s == .available {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: timeKey)
        }
        return s
    }

    public static var downloadURL: String {
        if let env = ProcessInfo.processInfo.environment["GUJO_DOWNLOAD_URL"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let url = EndpointRouter.downloadsURL()?.absoluteString, !url.isEmpty {
            return url
        }
        let appsBase = EndpointRouter.apps
        if !appsBase.isEmpty {
            return EndpointRouter.joining(appsBase, path: "downloads")?.absoluteString ?? appsBase
        }
        return EndpointRouter.apps
    }
}
#endif
