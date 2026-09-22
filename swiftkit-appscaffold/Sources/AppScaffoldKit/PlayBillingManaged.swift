import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// **Google Play 채널** 권한 원장 — Play Billing.
///
/// macOS/iOS 함대에는 BillingClient 가 없다. Android 쪽은 구매 토큰을
/// `recordPurchase` 로 주입하거나 JNI/FFI 브리지로 이 원장에 기록한다.
///
/// ## 채택
/// ```swift
/// ContentView().playBillingManaged()
/// // 또는 .entitlementManaged(channel: .play)
/// ```
///
/// ## Info.plist
/// - `PlayBillingProductIDs` / `PlayBillingProductID`
/// - `PlayBillingEnforceEntitlement` : `true` 일 때만 페이월 (기본 false)
///
/// ## Android (참고)
/// ```gradle
/// implementation("com.android.billingclient:billing-ktx:7.1.1")
/// ```
/// 구매 성공 시 네이티브 브리지로 `PlayBillingManaged.recordPurchase(productID:token:)` 호출.
///
/// 환경 `GUJO_ENFORCE_PLAY=1` 은 plist 플래그를 덮어쓴다.
public enum PlayBillingManaged {
    public enum Status: String, Sendable, Equatable {
        case available
        case notEntitled
        case unavailable
    }

    private static let cacheKey = "gujo.play.lastKnownStatus"
    private static let tokensKey = "gujo.play.purchaseTokens"

    public static var lastKnown: Status? {
        UserDefaults.standard.string(forKey: cacheKey).flatMap { Status(rawValue: $0) }
    }

    public static func productIDs(from bundle: Bundle = .main) -> Set<String> {
        if let arr = bundle.object(forInfoDictionaryKey: "PlayBillingProductIDs") as? [String] {
            return Set(arr.filter { !$0.isEmpty })
        }
        if let one = bundle.object(forInfoDictionaryKey: "PlayBillingProductID") as? String,
           !one.isEmpty {
            return [one]
        }
        return []
    }

    public static func isEnforced(bundle: Bundle = .main) -> Bool {
        if ProcessInfo.processInfo.environment["GUJO_ENFORCE_PLAY"] == "1" { return true }
        if let flag = bundle.object(forInfoDictionaryKey: "PlayBillingEnforceEntitlement") as? Bool {
            return flag
        }
        if let raw = bundle.object(forInfoDictionaryKey: "PlayBillingEnforceEntitlement") as? String {
            return ["1", "true", "yes", "YES"].contains(raw)
        }
        return false
    }

    /// Android BillingClient / 테스트 훅 — 구매 토큰 기록.
    public static func recordPurchase(productID: String, token: String) {
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map[productID] = token
        UserDefaults.standard.set(map, forKey: tokensKey)
    }

    public static func clearPurchases() {
        UserDefaults.standard.removeObject(forKey: tokensKey)
    }

    public static func recordedProductIDs() -> Set<String> {
        let map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        return Set(map.keys.filter { !$0.isEmpty && !(map[$0] ?? "").isEmpty })
    }

    /// - productIDs 비어 있음 → true
    /// - enforce 꺼짐 → true
    /// - enforce 켜짐 → 기록된 구매 토큰이 요구 상품과 겹치면 true
    public static func hasEntitlement(
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> Bool {
        let ids = productIDs ?? Self.productIDs(from: bundle)
        guard !ids.isEmpty else { return true }
        guard isEnforced(bundle: bundle) else { return true }
        let owned = recordedProductIDs()
        return !ids.isDisjoint(with: owned)
    }

    public static func status(
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> Status {
        let ids = productIDs ?? Self.productIDs(from: bundle)
        if ids.isEmpty || !isEnforced(bundle: bundle) {
            return remember(.available)
        }
        let ok = await hasEntitlement(productIDs: ids, bundle: bundle)
        return remember(ok ? .available : .notEntitled)
    }

    private static func remember(_ s: Status) -> Status {
        UserDefaults.standard.set(s.rawValue, forKey: cacheKey)
        return s
    }
}

#if canImport(SwiftUI)
extension View {
    @MainActor
    public func playBillingManaged(productIDs: Set<String>? = nil) -> some View {
        PlayBillingManagedGateView(productIDs: productIDs) { self }
    }
}

@MainActor
private struct PlayBillingManagedGateView<Content: View>: View {
    let content: Content
    let productIDs: Set<String>?
    @State private var status: PlayBillingManaged.Status = .available

    init(productIDs: Set<String>?, @ViewBuilder content: () -> Content) {
        self.productIDs = productIDs
        self.content = content()
    }

    var body: some View {
        Group {
            if status == .available {
                content
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(status == .notEntitled
                         ? "Google Play 에서 이 앱(또는 구독)을 구매해 주세요."
                         : "Play 권한을 확인할 수 없습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Google Play · Billing")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
        }
        .task {
            status = await PlayBillingManaged.status(productIDs: productIDs)
        }
    }
}
#endif
