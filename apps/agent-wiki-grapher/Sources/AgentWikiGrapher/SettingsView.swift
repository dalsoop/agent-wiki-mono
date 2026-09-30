import SwiftUI
import LocalizationKit
import SettingsUIKit
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        StandardSettingsForm(
            languageTitle: model.L(.settingsLanguage),
            language: Binding(
                get: { model.loc.language },
                set: { model.loc.setLanguage($0) }
            ),
            translationCoverage: TranslationCoverage(hardcodedUICount: 3),
            launchAtLoginTitle: model.L(.settingsLaunchAtLogin)
        ) {
            // 앱 전용 Section 은 여기에만 추가한다.
            EmptyView()
        }
        .padding()
        // Sparkle 자동업데이트 시작. SUFeedURL 은 build-macos-app.sh 가 공개 배포 빌드에서
        // Info.plist 에 주입한다(없으면 no-op). 수동 체크는 Sparkle 기본 "업데이트 확인" 메뉴.
    }
}
