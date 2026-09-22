import SwiftUI
import LocalizationKit

/// 재사용 시스템 확장 승인 온보딩 화면. 시스템 확장을 쓰는 어떤 앱이든 이걸 띄우면
/// 동일한 first-run 흐름을 얻는다 — 상태 안내, "설정 열기" 버튼, 승인되면 자동 종료.
/// 상태 폴링은 호출 앱이 담당(모델이 status 를 갱신) — 이 뷰는 그 상태를 그린다.
public struct SystemExtensionOnboardingView: View {
    private let ext: SystemExtension
    private let state: SystemExtension.ApprovalState
    private let language: AppLanguage
    private let onApprove: () -> Void
    private let onSkip: (() -> Void)?
    private let footer: AnyView?

    public init(ext: SystemExtension,
                state: SystemExtension.ApprovalState,
                language: AppLanguage = .system,
                onApprove: @escaping () -> Void,
                onSkip: (() -> Void)? = nil) {
        self.ext = ext
        self.state = state
        self.language = language
        self.onApprove = onApprove
        self.onSkip = onSkip
        self.footer = nil
    }

    /// 앱별 옵션(예: "로그인할 때 자동 실행")을 이 화면 안에 끼운다 — 승인 직후 사용자가 다시
    /// 설정을 찾아 들어가지 않게. 없으면 아무것도 안 그린다.
    public init<Footer: View>(ext: SystemExtension,
                             state: SystemExtension.ApprovalState,
                             language: AppLanguage = .system,
                             onApprove: @escaping () -> Void,
                             onSkip: (() -> Void)? = nil,
                             @ViewBuilder footer: () -> Footer) {
        self.ext = ext
        self.state = state
        self.language = language
        self.onApprove = onApprove
        self.onSkip = onSkip
        self.footer = AnyView(footer())
    }

    private var copy: SystemExtension.Copy { ext.copy(language: language) }
    private var korean: Bool { SystemExtension.isKorean(language) }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.isReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(state.isReady ? .green : .orange)
                .symbolRenderingMode(.hierarchical)

            Text(state.isReady ? (korean ? "확장이 활성화되었습니다" : "Extension enabled") : copy.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if !state.isReady {
                Text(copy.body)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // 3단계 안내 — 배너 한 줄로는 "어디서 무엇을 켜나"에 답이 안 된다.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(copy.steps.enumerated()), id: \.offset) { index, step in
                        Label {
                            Text(step).font(.callout)
                        } icon: {
                            Image(systemName: "\(index + 1).circle.fill").foregroundStyle(.tint)
                        }
                    }
                    settingsMock   // 실제로 시트에서 보게 될 행 — 글보다 그림이 빠르다
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                statusRow

                Button(action: onApprove) {
                    Label(copy.openButton, systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Text(copy.oneTime)
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text(korean ? "이제 이 앱을 사용할 수 있습니다." : "You can now use the app.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if let footer, !state.isReady {
                footer.frame(maxWidth: .infinity, alignment: .leading)
            }

            if let onSkip, !state.isReady {
                Button(korean ? "나중에" : "Later", action: onSkip)
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(28)
        .frame(width: 380)
    }

    /// 사용자가 System Settings 시트에서 실제로 보게 될 행 미리보기(초록 토글).
    private var settingsMock: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text(copy.mockRowLabel).font(.callout)
            Spacer()
            Capsule().fill(.green).frame(width: 36, height: 22)
                .overlay(Circle().fill(.white).frame(width: 18, height: 18).offset(x: 7))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
        .padding(.leading, 26)
    }

    @ViewBuilder private var statusRow: some View {
        let (text, color): (String, Color) = {
            switch state {
            case .unprobed:           return (korean ? "상태: 확인 중" : "Status: checking", .secondary)
            case .waitingForApproval: return (korean ? "상태: 설정에서 승인 대기" : "Status: waiting for approval in Settings", .orange)
            case .notInstalled:       return (korean ? "상태: 미설치 — 승인하면 설치됩니다" : "Status: not installed — approving installs it", .secondary)
            case .other(let s):       return ("상태: \(s)", .secondary)
            case .enabled:            return (korean ? "활성화됨" : "Enabled", .green)
            }
        }()
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
