#if os(macOS)
import ServiceManagement
#endif

/// 로그인 항목 등록을 추상화 — 테스트에서 목으로 대체 가능(CommandKit 의 `CommandRunning` 패턴과 동일).
public protocol LoginItemRegistering: Sendable {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

#if os(macOS)
/// 메인 앱 번들을 로그인 항목으로 등록하는 표준 구현(macOS `SMAppService`).
public struct MainAppLoginItem: LoginItemRegistering {
    public init() {}
    public var isRegistered: Bool { SMAppService.mainApp.status == .enabled }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}
#else
/// iOS 에는 로그인 항목 개념이 없다 — SettingsUIKit 을 공유하는 iOS 앱의 그래프 호환용 no-op.
public struct MainAppLoginItem: LoginItemRegistering {
    public init() {}
    public var isRegistered: Bool { false }
    public func register() throws {}
    public func unregister() throws {}
}
#endif

/// 로그인 시 자동 실행(Launch at Login)을 macOS 표준 API 로 관리한다.
///
/// 상주(메뉴바) 앱들이 제각각 `SMAppService.mainApp` 을 호출하던 중복을 swiftkit 공통으로 흡수한다.
/// 사용:
/// ```swift
/// LaunchAtLogin.mainApp.isEnabled          // 현재 상태
/// LaunchAtLogin.mainApp.setEnabled(true)   // 켜기 (결과 상태 반환)
/// ```
public struct LaunchAtLogin: Sendable {
    private let registrar: LoginItemRegistering

    public init(registrar: LoginItemRegistering = MainAppLoginItem()) {
        self.registrar = registrar
    }

    /// 현재 로그인 항목으로 등록돼 있는지.
    public var isEnabled: Bool { registrar.isRegistered }

    /// 등록/해제. 실패(미서명·권한 등)는 삼키고, **실제 결과 상태**를 반환한다.
    /// UI 는 이 반환값(또는 `isEnabled`)으로 토글을 되돌릴 수 있다.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled, !registrar.isRegistered {
                try registrar.register()
            } else if !enabled, registrar.isRegistered {
                try registrar.unregister()
            }
        } catch {
            // 등록 실패는 조용히 무시 — 호출부는 반환값으로 실제 상태를 반영한다.
        }
        return registrar.isRegistered
    }

    /// 현재 상태를 뒤집는다. 결과 상태를 반환.
    @discardableResult
    public func toggle() -> Bool { setEnabled(!isEnabled) }
}

extension LaunchAtLogin {
    /// 메인 앱 기준 공유 인스턴스(편의).
    public static let mainApp = LaunchAtLogin()
}
