import Foundation

/// 함대·허브 판정. Dock 정책을 읽거나 쓰지 않는다.
public enum FleetDeskIdentity: Sendable {
    public static func isHub(_ bundleId: String) -> Bool {
        let id = bundleId.lowercased()
        return id.contains("agent-apps-bar") || id.contains("agentappsbar")
    }

    public static func isFleet(_ bundleId: String) -> Bool {
        let id = bundleId.lowercased()
        return id.hasPrefix("net.ranode.") || id.hasPrefix("com.dalsoop.")
    }
}
