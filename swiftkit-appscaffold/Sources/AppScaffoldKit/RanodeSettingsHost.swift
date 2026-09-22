#if os(macOS)
import SwiftUI
#if SelfUpdating
import SparkleUpdateKit
public typealias SparkleCommands = SparkleUpdateKit.SparkleCommands
public typealias SparkleUpdateSection = SparkleUpdateKit.SparkleUpdateSection
public typealias CheckForUpdatesButton = SparkleUpdateKit.CheckForUpdatesButton
#endif

/// 설정 창에 함대 공통 업데이트 UI 를 붙이는 한 곳.
///
/// 앱이 `settingsView` 를 재정의해도 `Settings { }` 가 여기를 지나므로
/// 앱마다 토글·확인 버튼을 복붙하지 않는다.
public enum RanodeSettingsHost {
    @MainActor
    public static func wrap<V: View>(_ settingsView: V) -> some View {
        TenantStateRootEntry.applyIfNeeded()
        #if SelfUpdating
        SparkleReceiveBootstrap.install()
        return settingsView.withFleetUpdateSettings()
        #else
        return settingsView
        #endif
    }
}

#endif
