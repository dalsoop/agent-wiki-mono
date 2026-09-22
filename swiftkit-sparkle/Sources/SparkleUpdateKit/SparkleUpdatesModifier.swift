#if canImport(AppKit)
import SwiftUI
import AppKit
import SettingsUIKit

/// SwiftUI 화면 어디든 **한 줄**로 Sparkle 업데이트를 켜는 modifier.
///
/// 내부적으로는 `SparkleUpdaterHost.shared.start()` 를 onAppear 에서 한 번 부를 뿐.
/// 업데이트 다이얼로그·배너 UI 는 Sparkle 자체 UI 에 맡긴다(동작/체크주기는
/// `SUEnableAutomaticChecks`/`SUUpdateCheckInterval` Info.plist 키로 제어).
///
/// "업데이트 확인" 메뉴는 `SparkleCommands` 를 Scene 에 `.commands` 로 붙인다
/// — scaffold(`RanodeApp`)가 자동 처리.
public struct SparkleUpdatesModifier: ViewModifier {
    private let alwaysShowBanner: Bool

    public init(alwaysShowBanner: Bool = false) {
        self.alwaysShowBanner = alwaysShowBanner
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                SparkleUpdaterHost.shared.start()
            }
    }
}

public extension View {
    /// Sparkle 업데이터를 시작한다. `SUFeedURL` 이 없으면 no-op(개발 빌드).
    func sparkleUpdates(alwaysShowBanner: Bool = false) -> some View {
        modifier(SparkleUpdatesModifier(alwaysShowBanner: alwaysShowBanner))
    }

    /// 설정 Form 안에 함대 공통 업데이트 섹션을 넣는다.
    /// `StandardSettingsForm` 은 같은 Form 에 붙고, 커스텀 설정만 아래에 grouped Form 한 덩어리를 둔다.
    func withFleetUpdateSettings() -> some View {
        FleetUpdateSettingsContainer { self }
    }
}

/// 표준 폼이 footer 를 소비하면 한 섹션만 그린다. 아니면 설정 창 아래에 grouped Form 을 둔다.
private struct FleetUpdateSettingsContainer<Content: View>: View {
    let content: Content
    @State private var consumed = false
    @State private var allowFallback = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if consumed || !allowFallback {
                content
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    Form {
                        SparkleUpdateSection()
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .environment(\.settingsFormFooter, AnyView(SparkleUpdateSection()))
        .onPreferenceChange(SettingsFormFooterConsumedKey.self) { consumed = $0 }
        .onAppear {
            // One turn so StandardSettingsForm can mark the footer consumed
            // before fallback paints (avoids a first-frame duplicate Section).
            Task { @MainActor in
                allowFallback = true
            }
        }
    }
}

/// 앱 메뉴에 "업데이트 확인…" 항목을 넣는다. Scene 의 `.commands` 에 붙인다.
public struct SparkleCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
        }
    }
}

/// 설정에 넣는 함대 공통 업데이트 블록(자동 확인 토글 + 지금 확인).
///
/// 앱마다 버튼을 만들지 않는다. `RanodeSettingsHost.wrap` 이 붙인다.
public struct SparkleUpdateSection: View {
    public init() {}

    @State private var hasChannel = false

    public var body: some View {
        Section {
            if !hasChannel {
                Text(SparkleL10n.t("sparkle.no_channel_visible"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SparkleAutoUpdateToggle()
            CheckForUpdatesButton()
        } header: {
            Text(SparkleL10n.t("sparkle.section_title"))
        }
        .onAppear {
            SparkleL10n.syncFromDefaults()
            SparkleUpdaterHost.shared.start()
            hasChannel = SparkleUpdaterHost.shared.updater != nil
        }
    }
}

/// Sparkle updater 상태를 관찰해 canCheck 이 바뀌면 버튼 활성화가 따라간다.
public struct CheckForUpdatesButton: View {
    @State private var canCheck = false

    public init() {}

    public var body: some View {
        Button(SparkleL10n.t("sparkle.check_now")) {
            SparkleUpdaterHost.shared.checkForUpdates()
        }
        .disabled(!canCheck)
        .help(canCheck
              ? SparkleL10n.t("sparkle.check_help")
              : SparkleL10n.t("sparkle.no_channel_help"))
        .keyboardShortcut("U", modifiers: [.command])
        .onAppear {
            SparkleL10n.syncFromDefaults()
            SparkleUpdaterHost.shared.start()
            canCheck = SparkleUpdaterHost.shared.updater != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            canCheck = SparkleUpdaterHost.shared.updater != nil
        }
    }
}

#endif
