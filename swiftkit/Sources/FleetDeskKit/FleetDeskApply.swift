#if canImport(AppKit)
import AppKit
import Foundation

/// 이 프로세스의 activation policy. Dock 핀(plist)과 lsappinfo 실측은 다루지 않는다.
public enum FleetDeskApply {
    nonisolated(unsafe) private static var observingFlag = false

    public static func installHook() {
        FleetDeskActivationHook.install()
        observeFlagChanges()
    }

    public static func forcesAccessory(
        preferred: NSApplication.ActivationPolicy,
        bundleId: String = Bundle.main.bundleIdentifier ?? "",
        at url: URL? = nil
    ) -> Bool {
        if url == nil, bundleId == (Bundle.main.bundleIdentifier ?? "") {
            return preferred == .regular && FleetDeskShouldForceAccessoryC()
        }
        let current = FleetDeskStore.flag(at: url)
        return FleetDeskPolicy.forcesAccessory(
            bundleId: bundleId,
            hideEnabled: current.hideFleetDockIcons,
            dockBundleIds: current.resolvedDockBundleIds,
            preferredRegular: preferred == .regular
        )
    }

    /// 창 앱이 `.regular` 를 원할 때. 책상이 숨기면 훅이 accessory 로 꺾는다.
    @MainActor
    @discardableResult
    public static func applyPreferred(
        _ preferred: NSApplication.ActivationPolicy = .regular
    ) -> Bool {
        installHook()
        let policy: NSApplication.ActivationPolicy
        if forcesAccessory(preferred: preferred) {
            policy = .accessory
        } else {
            policy = preferred
        }
        return NSApplication.shared.setActivationPolicy(policy)
    }

    /// 숨길 대상일 때만 accessory. 메뉴바(LSUIElement)에 `.regular` 를 강요하지 않는다.
    @MainActor
    public static func hideThisProcessIfNeeded() {
        syncThisProcess()
    }

    /// 창을 앞으로. Dock 타일을 올리는 `activate(ignoringOtherApps:)` 는 쓰지 않는다.
    @MainActor
    public static func bringForward() {
        syncThisProcess()
        NSApplication.shared.activate()
    }

    /// JSON 의도에 맞춰 이 프로세스만 다시 맞춘다. 다른 앱에 주입하지 않는다.
    @MainActor
    public static func syncThisProcess() {
        installHook()
        let id = Bundle.main.bundleIdentifier ?? ""
        let current = FleetDeskStore.flag()
        let shouldHide = FleetDeskPolicy.shouldHideDockIcon(
            bundleId: id,
            hideEnabled: current.hideFleetDockIcons,
            dockBundleIds: current.resolvedDockBundleIds
        )
        let lsui = FleetDeskPolicy.isTruthyLSUIElement(
            Bundle.main.object(forInfoDictionaryKey: "LSUIElement")
        )
        switch FleetDeskPolicy.processDockAction(
            shouldHide: shouldHide,
            infoPlistUIElement: lsui
        ) {
        case .forceAccessory:
            _ = applyPreferred(.accessory)
        case .forceRegular:
            _ = applyPreferred(.regular)
        case .leave:
            break
        }
    }

    private static func observeFlagChanges() {
        guard !observingFlag else { return }
        observingFlag = true
        DistributedNotificationCenter.default().addObserver(
            forName: .fleetDeskDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                FleetDeskApply.syncThisProcess()
            }
        }
    }
}
#endif
