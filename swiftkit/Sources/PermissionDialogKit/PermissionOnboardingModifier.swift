import PermissionKit
import AppKit
import SwiftUI

public extension View {
    /// 선언된 필수 권한이 빠지면 본문 대신 `PermissionOnboardingView` 를 단다.
    /// 목록은 Info.plist `SwiftAppRequiredPermissions` 이고 앱이 다시 적지 않는다.
    func permissionOnboarding(appName: String? = nil) -> some View {
        let name = appName ?? PermissionOnboardingNames.bundleAppName
        return PermissionOnboardingGate(appName: name) { self }
    }
}

enum PermissionOnboardingNames {
    static var bundleAppName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }
}

struct PermissionOnboardingGate<Content: View>: View {
    let appName: String
    let content: Content
    @State private var showOnboarding = PermissionOnboardingGate.shouldShowInitially

    init(appName: String, @ViewBuilder content: () -> Content) {
        self.appName = appName
        self.content = content()
    }

    var body: some View {
        Group {
            if showOnboarding {
                PermissionOnboardingView(appName: appName) {
                    showOnboarding = false
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                ) { _ in
                    refresh()
                }
            } else {
                content
            }
        }
    }

    private func refresh() {
        let required = PermissionRequirements.declared().required
        let missingNonFDA = required.contains { permission in
            if permission == .fullDiskAccess { return false }
            if let granted = permission.grantedIfSafeToProbe { return !granted }
            return false
        }
        if missingNonFDA {
            showOnboarding = true
            return
        }
        if !required.contains(.fullDiskAccess) {
            showOnboarding = false
        }
    }

    /// FDA 조회는 시작 경로에서 하지 않는다. 필수에 FDA 가 있으면 온보딩을 연다.
    static var shouldShowInitially: Bool {
        PermissionRequirements.declared().required.contains { permission in
            switch permission.grantedIfSafeToProbe {
            case .some(false): return true
            case .some(true): return false
            case .none: return true
            }
        }
    }
}
