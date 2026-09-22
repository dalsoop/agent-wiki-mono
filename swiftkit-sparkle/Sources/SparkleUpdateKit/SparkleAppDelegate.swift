#if canImport(AppKit)
import AppKit
import AppWindowKit

/// Sparkle 자동업데이트가 켜진 표준 창 앱 AppDelegate.
///
/// `swiftkit` 의 `StandardWindowAppDelegate` 를 상속해, launch 직후
/// `SparkleUpdaterHost.shared.start()` 한 줄만 덧붙인다. 기존 창 앱(~130종)은
/// 마이그레이션 시 상위클래스만 이쪽으로 바꾸면 된다:
///
/// ```swift
/// @NSApplicationDelegateAdaptor(MyAppDelegate.self) private var delegate
/// final class MyAppDelegate: SparkleUpdaterAppDelegate { ... }
/// ```
///
/// 옵트아웃은 `enablesSparkleUpdates = false` (예: 개발 도구 dev 빌드).
open class SparkleUpdaterAppDelegate: StandardWindowAppDelegate {
    /// launch 시 Sparkle 업데이터를 시작할지. dev 빌드 등은 false 로 끈다.
    open var enablesSparkleUpdates: Bool { true }

    open override func applicationDidFinishLaunching(_ notification: Notification) {
        super.applicationDidFinishLaunching(notification)
        guard enablesSparkleUpdates else { return }
        SparkleUpdaterHost.shared.start()
    }
}

#endif
