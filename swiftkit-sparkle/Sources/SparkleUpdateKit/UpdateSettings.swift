#if canImport(AppKit)
import Foundation
import SwiftUI
import Sparkle

/// 설정창의 "업데이트 자동 확인" 토글을 Sparkle 과 잇는 얇은 브릿지.
///
/// Sparkle 은 `SPUUpdater.automaticallyChecksForUpdates` 로 자체 관리하므로,
/// 별도 UserDefaults 를 두지 않고 그 값을 그대로 노출한다. 시작 전(updater == nil)
/// 이면 읽기는 기본 true, 쓰기는 no-op.
public struct UpdateSettings: Sendable {
    public init() {}

    public var automaticallyChecks: Bool {
        get { MainActor.assumeIsolated { SparkleUpdaterHost.shared.updater?.automaticallyChecksForUpdates ?? true } }
    }

    @MainActor
    public func setAutomaticallyChecks(_ value: Bool) {
        SparkleUpdaterHost.shared.updater?.automaticallyChecksForUpdates = value
    }
}

/// 설정 화면에 넣을 수 있는 자동 업데이트 토글 뷰.
public struct SparkleAutoUpdateToggle: View {
    @State private var isOn: Bool = true
    @State private var hasChannel = false

    public init() {}

    public var body: some View {
        Toggle(SparkleL10n.t("sparkle.auto_check"), isOn: $isOn)
            .disabled(!hasChannel)
            .help(hasChannel ? "" : SparkleL10n.t("sparkle.no_channel_help"))
            .onAppear {
                SparkleL10n.syncFromDefaults()
                SparkleUpdaterHost.shared.start()
                hasChannel = SparkleUpdaterHost.shared.updater != nil
                isOn = UpdateSettings().automaticallyChecks
            }
            .onChange(of: isOn) { _, newValue in
                UpdateSettings().setAutomaticallyChecks(newValue)
            }
    }
}

#endif
