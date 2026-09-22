import Foundation

/// 순수 규칙. 파일·AppKit·lsappinfo 에 닿지 않는다.
public enum FleetDeskPolicy: Sendable {
    /// 책상 모드에서도 Dock에 남는 함대 앱. 허브는 목록과 무관하게 남는다.
    public static let defaultDockBundleIds = [
        "net.ranode.agent-worker-orchestrator",
        "net.ranode.agent-chat",
    ]

    public static func shouldHideDockIcon(
        bundleId: String,
        hideEnabled: Bool,
        dockBundleIds: [String] = []
    ) -> Bool {
        guard hideEnabled, FleetDeskIdentity.isFleet(bundleId), !FleetDeskIdentity.isHub(bundleId) else {
            return false
        }
        let allowed = Set(dockBundleIds.map { $0.lowercased() })
        if allowed.contains(bundleId.lowercased()) { return false }
        return true
    }

    /// `setActivationPolicy(.regular)` 요청을 Accessory 로 꺾어야 하는지.
    public static func forcesAccessory(
        bundleId: String,
        hideEnabled: Bool,
        dockBundleIds: [String] = [],
        preferredRegular: Bool = true
    ) -> Bool {
        preferredRegular
            && shouldHideDockIcon(
                bundleId: bundleId,
                hideEnabled: hideEnabled,
                dockBundleIds: dockBundleIds
            )
    }

    /// 이 프로세스가 지금 취해야 할 Dock 타일 동작.
    /// 메뉴바(`LSUIElement`)는 숨김이 꺼져도 `.regular` 로 올리지 않는다.
    public enum ProcessDockAction: Equatable, Sendable {
        case forceAccessory
        case forceRegular
        case leave
    }

    public static func processDockAction(
        shouldHide: Bool,
        infoPlistUIElement: Bool
    ) -> ProcessDockAction {
        if shouldHide { return .forceAccessory }
        if infoPlistUIElement { return .leave }
        return .forceRegular
    }

    public static func isTruthyLSUIElement(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "1" || trimmed == "true" || trimmed == "yes"
        }
        return false
    }
}
