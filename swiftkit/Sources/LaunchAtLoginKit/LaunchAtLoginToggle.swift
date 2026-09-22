#if canImport(SwiftUI)
import SwiftUI

/// "로그인 시 자동 실행" 토글 드롭인 뷰.
///
/// 상주 앱 설정 화면에 한 줄로 꽂는다:
/// ```swift
/// LaunchAtLoginToggle("로그인 시 자동 실행")
/// ```
/// 라벨은 호출부가 직접 넘긴다(LocalizationKit 으로 번역한 문자열을 그대로 전달하면 KR/EN 전환도 동작).
public struct LaunchAtLoginToggle: View {
    private let title: String
    private let launcher: LaunchAtLogin
    @State private var isOn: Bool

    public init(_ title: String = "Launch at login", launcher: LaunchAtLogin = .mainApp) {
        self.title = title
        self.launcher = launcher
        _isOn = State(initialValue: launcher.isEnabled)
    }

    public var body: some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { isOn = launcher.setEnabled($0) }
        ))
        // 시스템 설정에서 외부로 바뀐 경우까지 매번 실제 상태로 재동기화.
        .onAppear { isOn = launcher.isEnabled }
    }
}
#endif
