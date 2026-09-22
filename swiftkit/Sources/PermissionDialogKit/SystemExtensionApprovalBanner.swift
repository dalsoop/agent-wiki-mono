import PermissionKit
import SwiftUI
import LocalizationKit

/// 미승인 상태를 알리는 **한 줄 배너**(메뉴바·주 창 상단 공용).
///
/// 배경(백로그 45873825): vpn-wireguard 안에 같은 취지의 안내가 3벌 있었다 —
/// `WelcomeGuideView`(3단계 그림), `MainWindowView` 인라인 HStack, `MenuBarView` 배너.
/// 문구가 서로 달라 어디를 보느냐에 따라 다른 말을 들었다. 상세 안내는
/// `SystemExtensionOnboardingView` 하나로, 좁은 자리에 끼우는 알림은 이 배너 하나로 모은다.
public struct SystemExtensionApprovalBanner: View {
    private let ext: SystemExtension
    private let language: AppLanguage
    private let action: () -> Void

    public init(ext: SystemExtension, language: AppLanguage = .system, action: @escaping () -> Void) {
        self.ext = ext
        self.language = language
        self.action = action
    }

    public var body: some View {
        let copy = ext.copy(language: language)
        let korean = SystemExtension.isKorean(language)
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.title).font(.callout.bold()).foregroundStyle(.orange)
                Text(korean ? "승인은 최초 1회뿐입니다" : "One-time approval")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(korean ? "승인하기" : "Approve", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
