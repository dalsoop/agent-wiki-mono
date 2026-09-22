import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// **App Store 채널** 권한 원장 — StoreKit 2.
///
/// `GujoManaged`(Mac 직판 · Cloud Apps) 와 **대칭**이지만 원장이 다르다.
/// iOS/iPadOS 판매 빌드와 Mac App Store 빌드는 이쪽을 쓴다.
///
/// ## 채택
/// ```swift
/// ContentView()
///     .entitlementManaged()                 // 권장 — 채널 자동 라우팅
///     .appStoreManaged()                    // 하위 호환
/// ```
///
/// ## Info.plist
/// - `AppStoreProductIDs` : `[String]` 구독·비소모 상품 ID (카탈로그)
/// - `AppStoreProductID` : 단일 문자열
/// - `AppStoreEnforceEntitlement` : `true` 일 때만 페이월 (기본 false — 카탈로그만 박아도 벽돌 없음)
///
/// 환경 `GUJO_ENFORCE_STOREKIT=1` 은 plist 플래그를 덮어쓴다(샌드박스 E2E).
public enum AppStoreManaged {
    public enum Status: String, Sendable, Equatable {
        case available
        case notEntitled
        case unavailable
    }

    private static let cacheKey = "gujo.appstore.lastKnownStatus"

    public static var lastKnown: Status? {
        UserDefaults.standard.string(forKey: cacheKey).flatMap {
            Status(rawValue: $0)
        }
    }

    /// Bundle 에서 상품 ID 읽기.
    public static func productIDs(from bundle: Bundle = .main) -> Set<String> {
        if let arr = bundle.object(forInfoDictionaryKey: "AppStoreProductIDs") as? [String] {
            return Set(arr.filter { !$0.isEmpty })
        }
        if let one = bundle.object(forInfoDictionaryKey: "AppStoreProductID") as? String,
           !one.isEmpty {
            return [one]
        }
        return []
    }

    /// 페이월을 실제로 걸 것인가. 상품 ID 만 있고 enforce 없으면 카탈로그만(fail-open).
    public static func isEnforced(bundle: Bundle = .main) -> Bool {
        if ProcessInfo.processInfo.environment["GUJO_ENFORCE_STOREKIT"] == "1" {
            return true
        }
        if let flag = bundle.object(forInfoDictionaryKey: "AppStoreEnforceEntitlement") as? Bool {
            return flag
        }
        if let raw = bundle.object(forInfoDictionaryKey: "AppStoreEnforceEntitlement") as? String {
            return ["1", "true", "yes", "YES"].contains(raw)
        }
        return false
    }

    /// 유효 entitlement 가 있는가.
    ///
    /// - productIDs 비어 있음 → `true`
    /// - enforce 꺼짐 → `true` (카탈로그 전용)
    /// - StoreKit 없음 플랫폼 → `true`
    public static func hasEntitlement(
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> Bool {
        let ids = productIDs ?? Self.productIDs(from: bundle)
        guard !ids.isEmpty else { return true }
        guard isEnforced(bundle: bundle) else { return true }
        #if canImport(StoreKit)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ids.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil { return true }
        }
        return false
        #else
        return true
        #endif
    }

    public static func status(
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> Status {
        let ids = productIDs ?? Self.productIDs(from: bundle)
        if ids.isEmpty || !isEnforced(bundle: bundle) {
            return remember(.available)
        }
        #if canImport(StoreKit)
        let ok = await hasEntitlement(productIDs: ids, bundle: bundle)
        return remember(ok ? .available : .notEntitled)
        #else
        return remember(.available)
        #endif
    }

    private static func remember(_ s: Status) -> Status {
        UserDefaults.standard.set(s.rawValue, forKey: cacheKey)
        return s
    }
}

#if canImport(SwiftUI)
extension View {
    /// App Store 채널 한 줄 채택. 직판의 `.gujoManaged()` 와 대칭.
    @MainActor
    public func appStoreManaged(productIDs: Set<String>? = nil) -> some View {
        AppStoreManagedGateView(productIDs: productIDs) { self }
    }
}

@MainActor
private struct AppStoreManagedGateView<Content: View>: View {
    let content: Content
    let productIDs: Set<String>?
    @State private var status: AppStoreManaged.Status

    init(productIDs: Set<String>?, @ViewBuilder content: () -> Content) {
        self.productIDs = productIDs
        self.content = content()
        _status = State(initialValue: AppStoreManaged.lastKnown ?? .available)
    }

    var body: some View {
        Group {
            if status == .available {
                content
            } else {
                AppStoreManagedWaitingView(status: status)
            }
        }
        .task {
            status = await AppStoreManaged.status(productIDs: productIDs)
        }
    }
}

private struct AppStoreManagedWaitingView: View {
    let status: AppStoreManaged.Status

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("App Store · StoreKit")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 280, minHeight: 160)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        switch status {
        case .available: ""
        case .notEntitled: "App Store 에서 이 앱(또는 구독)을 구매해 주세요."
        case .unavailable: "App Store 연결을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}
#endif
