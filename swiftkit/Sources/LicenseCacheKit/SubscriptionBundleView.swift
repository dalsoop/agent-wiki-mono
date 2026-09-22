#if canImport(SwiftUI)
import SwiftUI

/// 번들 구독 카드를 표시하는 공용 SwiftUI 컴포넌트.
///
/// 번들 이름, 가격, 포함 앱 수, 구독 상태 배지를 한 카드에 보여주고,
/// 비구독 상태면 구매 링크를 제공한다.
@MainActor
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct SubscriptionBundleView: View {
    private let bundle: SubscriptionBundle
    private let purchaseURL: URL?

    public init(bundle: SubscriptionBundle, purchaseURL: URL? = nil) {
        self.bundle = bundle
        self.purchaseURL = purchaseURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.name)
                        .font(.headline)
                    Text(bundle.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(minWidth: 20)
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 16) {
                Label("\(bundle.productIDs.count)개 앱", systemImage: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let monthly = bundle.priceMonthly {
                    Text("₩\(monthly as NSDecimalNumber)/월")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let yearly = bundle.priceYearly {
                    Text("₩\(yearly as NSDecimalNumber)/년")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let expiresAt = bundle.expiresAt, bundle.isActive {
                Text("갱신: \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !bundle.isActive, let purchaseURL {
                Link("구독하기", destination: purchaseURL)
                    .font(.callout)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(bundle.isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.2))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundle.name), \(bundle.isActive ? "구독 중" : "미구독"), \(bundle.productIDs.count)개 앱 포함")
    }

    private var statusBadge: some View {
        Group {
            if bundle.isActive {
                Label("구독 중", systemImage: "checkmark.seal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.1), in: Capsule())
            } else {
                Text("미구독")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
        }
    }
}

/// 번들 목록을 로딩 상태와 함께 보여주는 컨테이너 뷰.
@MainActor
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct SubscriptionBundleListView: View {
    private let manager: BundleSubscriptionManager
    private let purchaseBaseURL: URL?

    public init(manager: BundleSubscriptionManager, purchaseBaseURL: URL? = nil) {
        self.manager = manager
        self.purchaseBaseURL = purchaseBaseURL
    }

    public var body: some View {
        VStack(spacing: 12) {
            if manager.isLoading {
                ProgressView("번들 정보 로딩 중...")
                    .controlSize(.small)
            } else if manager.bundles.isEmpty {
                ContentUnavailableView(
                    "사용 가능한 번들 없음",
                    systemImage: "cube.box",
                    description: Text(manager.lastError ?? "구독 가능한 번들이 없습니다.")
                )
            } else {
                ForEach(manager.bundles) { bundle in
                    SubscriptionBundleView(
                        bundle: bundle,
                        purchaseURL: bundlePurchaseURL(for: bundle)
                    )
                }
            }

            if let error = manager.lastError, !manager.bundles.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func bundlePurchaseURL(for bundle: SubscriptionBundle) -> URL? {
        guard let base = purchaseBaseURL else { return nil }
        return base.appendingPathComponent("bundles/\(bundle.id)")
    }
}
#endif
