import SwiftUI
import LocalizationKit
import SettingsUIKit
import SparkleUpdateKit

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        StandardSettingsForm(
            languageTitle: model.L(.settingsLanguage),
            language: Binding(
                get: { model.loc.language },
                set: { model.loc.setLanguage($0) }
            ),
            launchAtLoginTitle: model.L(.settingsLaunchAtLogin)
        ) {
            // 앱 전용 Section 은 여기에만 추가한다.
            EmptyView()
        }
        .padding()
        .sparkleUpdates()
    }
}
