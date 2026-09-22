import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// 함대 Dock 타일 숨김의 공개 입구. 층은 파일마다 나뉜다.
///
/// - 판정: `FleetDeskIdentity` · `FleetDeskPolicy`
/// - 의도 JSON: `FleetDeskStore`
/// - 이 프로세스: `FleetDeskApply` (activation policy 훅)
/// - 실측: `FleetDeskLiveProbe` (`lsappinfo` UIElement)
/// - Dock 핀(plist): Agent Apps Bar `FleetDockQuiet` — 이 키트 밖
public enum FleetDeskMode: Sendable {
    public typealias Flag = FleetDeskStore.Flag

    public static let defaultDockBundleIds = FleetDeskPolicy.defaultDockBundleIds

    public static func flagURL(home: URL = FleetDeskStore.posixHome()) -> URL {
        FleetDeskStore.flagURL(home: home)
    }

    public static func isHub(_ bundleId: String) -> Bool {
        FleetDeskIdentity.isHub(bundleId)
    }

    public static func isFleet(_ bundleId: String) -> Bool {
        FleetDeskIdentity.isFleet(bundleId)
    }

    public static func shouldHideDockIcon(
        bundleId: String,
        hideEnabled: Bool,
        dockBundleIds: [String] = []
    ) -> Bool {
        FleetDeskPolicy.shouldHideDockIcon(
            bundleId: bundleId,
            hideEnabled: hideEnabled,
            dockBundleIds: dockBundleIds
        )
    }

    public static func forcesAccessory(
        bundleId: String,
        hideEnabled: Bool,
        dockBundleIds: [String] = [],
        preferredRegular: Bool = true
    ) -> Bool {
        FleetDeskPolicy.forcesAccessory(
            bundleId: bundleId,
            hideEnabled: hideEnabled,
            dockBundleIds: dockBundleIds,
            preferredRegular: preferredRegular
        )
    }

    public static func installDockHook() {
        #if canImport(AppKit)
        FleetDeskApply.installHook()
        #endif
    }

    public static func flag(at url: URL? = nil) -> Flag {
        FleetDeskStore.flag(at: url)
    }

    public static func isEnabled(at url: URL? = nil) -> Bool {
        FleetDeskStore.isEnabled(at: url)
    }

    public static func shouldHideDockIcon(
        bundleId: String,
        at url: URL? = nil
    ) -> Bool {
        let current = FleetDeskStore.flag(at: url)
        return FleetDeskPolicy.shouldHideDockIcon(
            bundleId: bundleId,
            hideEnabled: current.hideFleetDockIcons,
            dockBundleIds: current.resolvedDockBundleIds
        )
    }

    public static func allowsDock(_ bundleId: String, at url: URL? = nil) -> Bool {
        !shouldHideDockIcon(bundleId: bundleId, at: url)
    }

    /// 책상 모드가 꺼져 있어도 목록 편집은 이 값을 본다.
    public static func isOnDockAllowlist(_ bundleId: String, at url: URL? = nil) -> Bool {
        if FleetDeskIdentity.isHub(bundleId) { return true }
        let id = bundleId.lowercased()
        return FleetDeskStore.flag(at: url).resolvedDockBundleIds.contains { $0.lowercased() == id }
    }

    public static func setEnabled(_ on: Bool, at url: URL? = nil) throws {
        try FleetDeskStore.setEnabled(on, at: url)
    }

    public static func hideAllFleet(at url: URL? = nil) throws {
        try FleetDeskStore.hideAllFleet(at: url)
    }

    public static func setDockAllowed(_ bundleId: String, allowed: Bool, at url: URL? = nil) throws {
        try FleetDeskStore.setDockAllowed(bundleId, allowed: allowed, at: url)
    }

    public static func save(_ current: Flag, at url: URL? = nil) throws {
        try FleetDeskStore.save(current, at: url)
    }

    #if canImport(AppKit)
    public static func forcesAccessory(
        preferred: NSApplication.ActivationPolicy,
        bundleId: String = Bundle.main.bundleIdentifier ?? "",
        at url: URL? = nil
    ) -> Bool {
        FleetDeskApply.forcesAccessory(preferred: preferred, bundleId: bundleId, at: url)
    }

    @MainActor
    @discardableResult
    public static func applyActivationPolicy(
        _ preferred: NSApplication.ActivationPolicy = .regular
    ) -> Bool {
        FleetDeskApply.applyPreferred(preferred)
    }
    #endif
}
