#if os(macOS)
import SwiftUI
#if canImport(PermissionKit)
import PermissionKit
#endif

/// 메뉴바 팝오버 공통 껍데기. ExtraApp / MenuBarApp / WindowGroupApp 이 같이 쓴다.
///
/// 기동 가드는 여기 한 번이다. 프로토콜마다 `FleetManagedAppBootstrap` 을 복붙하지 않는다.
struct RanodeMenuBarPopover<Content: View>: View {
    private let productName: String
    private let content: Content

    init(productName: String, @ViewBuilder content: () -> Content) {
        self.productName = productName
        self.content = content()
        FleetManagedAppBootstrap.runOnce()
        #if canImport(PermissionKit)
        _ = PermissionBootstrap.runIfRequested(appName: productName)
        #endif
    }

    @ViewBuilder var body: some View {
        #if canImport(PermissionKit)
        if PermissionBootstrap.isRequested {
            Color.clear.frame(width: 1, height: 1)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#endif
