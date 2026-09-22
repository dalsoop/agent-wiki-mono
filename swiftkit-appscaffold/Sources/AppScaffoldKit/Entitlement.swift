import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum EntitlementStatus: String, Sendable, Equatable, Codable {
    case available
    case notEntitled
    case notConnected
    case unavailable
    case authorityMissing
}

// MARK: - 단일 권한 façade (채널별 원장 라우팅)

/// 배포 채널. 빌드·Info.plist 에 박는다 (`EntitlementChannel` rawValue 와 맞춤).
///
/// - `Info.plist` 키 `EntitlementChannel` 또는 `SwiftAppDistributionPrimary`
/// - 환경/컴파일: 앱이 `productIDs` 등으로 세밀 제어
public enum EntitlementChannelKind: String, Sendable, Codable, CaseIterable {
    case appstore
    case direct
    case play
    case privateStore = "private"

    /// Bundle 에서 채널 읽기. 없으면 `.direct`(Mac 직판 함대 기본).
    public static func fromBundle(_ bundle: Bundle = .main) -> EntitlementChannelKind {
        let keys = ["EntitlementChannel", "SwiftAppDistributionPrimary", "SwiftAppDistribution"]
        for key in keys {
            if let raw = bundle.object(forInfoDictionaryKey: key) as? String,
               let ch = EntitlementChannelKind(rawValue: raw.lowercased())
                ?? mapAlias(raw) {
                return ch
            }
        }
        if let arr = bundle.object(forInfoDictionaryKey: "SwiftAppDistributionChannels") as? [String],
           let first = arr.first,
           let ch = EntitlementChannelKind(rawValue: first.lowercased()) ?? mapAlias(first) {
            return ch
        }
        return .direct
    }

    private static func mapAlias(_ raw: String) -> EntitlementChannelKind? {
        switch raw.lowercased() {
        case "app-store": return .appstore
        case "googleplay", "google-play": return .play
        case "privatestore", "private-store", "fdroid", "sideload": return .privateStore
        default: return nil
        }
    }
}

/// **앱이 아는 유일한 권한 API.**
///
/// 채널에 따라 원장을 고른다:
/// - `direct` → `GujoManaged` (Cloud Apps)
/// - `appstore` → `AppStoreManaged` (StoreKit)
/// - `play` → `PlayBillingManaged` (Play Billing · 현재 fail-open 스캐폴드)
/// - `private` → `PrivateLicenseManaged` (서명 라이선스 · 현재 fail-open 스캐폴드)
///
/// ```swift
/// ContentView().entitlementManaged()
/// // 또는 채널 고정:
/// ContentView().entitlementManaged(channel: .appstore)
/// ```
public enum Entitlement {
    /// 현재 번들의 채널에 맞는 권한 판정.
    public static func status(
        channel: EntitlementChannelKind? = nil,
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> EntitlementStatus {
        let ch = channel ?? EntitlementChannelKind.fromBundle(bundle)
        switch ch {
        case .direct:
            #if GujoManaged
            let s = await GujoManaged.status()
            switch s {
            case .available: return .available
            case .notEntitled: return .notEntitled
            case .notConnected: return .notConnected
            case .cloudAppsMissing: return .authorityMissing
            }
            #else
            // GujoManaged trait 없이 직판 판정 불가 — 관대.
            return .available
            #endif

        case .appstore:
            let s = await AppStoreManaged.status(productIDs: productIDs, bundle: bundle)
            switch s {
            case .available: return .available
            case .notEntitled: return .notEntitled
            case .unavailable: return .unavailable
            }

        case .play:
            let s = await PlayBillingManaged.status(productIDs: productIDs, bundle: bundle)
            switch s {
            case .available: return .available
            case .notEntitled: return .notEntitled
            case .unavailable: return .unavailable
            }

        case .privateStore:
            let s = await PrivateLicenseManaged.status(bundle: bundle)
            switch s {
            case .available: return .available
            case .notEntitled: return .notEntitled
            case .unavailable: return .unavailable
            }
        }
    }

    public static func isAvailable(
        channel: EntitlementChannelKind? = nil,
        productIDs: Set<String>? = nil,
        bundle: Bundle = .main
    ) async -> Bool {
        await status(channel: channel, productIDs: productIDs, bundle: bundle) == .available
    }
}

#if canImport(SwiftUI)
extension View {
    /// 채널 자동 라우팅 권한 게이트. 직판=Cloud Apps, App Store=StoreKit.
    @MainActor
    public func entitlementManaged(
        channel: EntitlementChannelKind? = nil,
        productIDs: Set<String>? = nil
    ) -> some View {
        EntitlementGateView(channel: channel, productIDs: productIDs) { self }
    }
}

@MainActor
private struct EntitlementGateView<Content: View>: View {
    let content: Content
    let channel: EntitlementChannelKind?
    let productIDs: Set<String>?
    @State private var status: EntitlementStatus
    @State private var resolved: Bool

    private static var lastKnown: EntitlementStatus? {
        UserDefaults.standard.string(forKey: "entitlement.lastKnownStatus")
            .flatMap { EntitlementStatus(rawValue: $0) }
    }

    init(
        channel: EntitlementChannelKind?,
        productIDs: Set<String>?,
        @ViewBuilder content: () -> Content
    ) {
        self.channel = channel
        self.productIDs = productIDs
        self.content = content()
        let cached = Self.lastKnown
        _status = State(initialValue: cached ?? .available)
        _resolved = State(initialValue: cached != nil)
    }

    var body: some View {
        Group {
            if resolved && status == .available {
                content
            } else if !resolved {
                ProgressView()
                    .frame(minWidth: 280, minHeight: 160)
            } else {
                EntitlementWaitingView(status: status, channel: resolvedChannel)
            }
        }
        .task {
            let s = await Entitlement.status(channel: channel, productIDs: productIDs)
            status = s
            resolved = true
            UserDefaults.standard.set(s.rawValue, forKey: "entitlement.lastKnownStatus")
        }
    }

    private var resolvedChannel: EntitlementChannelKind {
        channel ?? EntitlementChannelKind.fromBundle()
    }
}

private struct EntitlementWaitingView: View {
    let status: EntitlementStatus
    let channel: EntitlementChannelKind

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(channelCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 280, minHeight: 160)
        .accessibilityElement(children: .combine)
    }

    private var channelCaption: String {
        switch channel {
        case .direct: return "직판 · Gujo Cloud Apps"
        case .appstore: return "App Store · StoreKit"
        case .play: return "Google Play · Billing"
        case .privateStore: return "사설 스토어 · 서명 라이선스"
        }
    }

    private var message: String {
        switch (channel, status) {
        case (.direct, .authorityMissing):
            return "Gujo Cloud Apps 설치가 필요합니다."
        case (.direct, .notConnected):
            return "Gujo Cloud Apps 에 로그인해주세요."
        case (.direct, .notEntitled):
            return "Gujo Cloud Apps 에서 이 앱을 연결해주세요."
        case (.appstore, .notEntitled):
            return "App Store 에서 이 앱(또는 구독)을 구매해 주세요."
        case (_, .unavailable):
            return "권한을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요."
        default:
            return "이 앱을 사용할 권한이 없습니다."
        }
    }
}
#endif
