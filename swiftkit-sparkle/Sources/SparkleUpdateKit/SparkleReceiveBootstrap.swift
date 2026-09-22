#if canImport(AppKit)
import AppKit
import SwiftUI

/// DualEntry·스테이지 앱이 Ranode wrap 없이 수신 Settings 를 붙이는 한 곳.
/// App body 에 `SparkleReceiveSettingsScene()` 또는 `SparkleReceiveSettings.wrap` 만 쓴다.
/// 앱마다 SparkleLaunch.swift 를 복사하지 않는다.
public enum SparkleReceiveSettings {
    @MainActor
    public static func wrap<V: View>(_ view: V) -> some View {
        SparkleReceiveBootstrap.install()
        return view.withFleetUpdateSettings()
    }
}

public struct SparkleReceiveSettingsScene: Scene {
    public init() {
        SparkleReceiveBootstrap.install()
    }

    public var body: some Scene {
        Settings {
            EmptyView().withFleetUpdateSettings()
        }
    }
}

public enum SparkleReceiveBootstrap {
    public static func install() {
        _ = SparkleLaunchHook.shared
    }
}

/// DualEntry 모듈은 Settings 씬이 launching 이후에 로드될 수 있다. 알림만 기다리면 start 를 놓친다.
final class SparkleLaunchHook: NSObject {
    nonisolated(unsafe) static let shared = SparkleLaunchHook()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(start),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
        start()
    }

    @objc private func start() {
        Task { @MainActor in
            SparkleUpdaterHost.shared.start()
        }
    }
}

#endif
