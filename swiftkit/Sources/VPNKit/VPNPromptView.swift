import SwiftUI

/// 2026-10-31까지 기존 소비 앱의 화면 소스 호환을 유지하는 전환용 래퍼.
///
/// 새 화면은 `VPNRecoveryView`와 `VPNConnectivityModel`을 직접 사용한다.
@available(
    *,
    deprecated,
    message: "Use VPNRecoveryView with VPNConnectivityModel; compatibility ends after 2026-10-31"
)
public struct VPNPromptView: View {
    @Bindable private var model: VPNGateModel
    private let onConnected: () -> Void
    private let onRetry: () -> Void
    private let compact: Bool

    /// 기존 init 서명은 마이그레이션 기간 동안 유지한다.
    public init(
        model: VPNGateModel,
        compact: Bool = false,
        onRetry: @escaping () -> Void = {},
        onConnected: @escaping () -> Void
    ) {
        self.model = model
        self.compact = compact
        self.onRetry = onRetry
        self.onConnected = onConnected
    }

    public var body: some View {
        if let connectivity = model.connectivity {
            VPNRecoveryView(
                model: connectivity,
                language: .system,
                compact: compact,
                onRetry: onRetry,
                onConnected: onConnected,
                connectAction: { serviceID in
                    if await model.connect(serviceID: serviceID) {
                        model.clear()
                        onConnected()
                    }
                },
                diagnoseAction: {
                    onRetry()
                }
            )
        }
    }
}
