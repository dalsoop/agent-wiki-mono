import Foundation

public struct VPNTarget: Codable, Hashable, Sendable {
    public let host: String
    public let port: Int
    public let displayName: String

    public init(host: String, port: Int, displayName: String) {
        self.host = host
        self.port = port
        self.displayName = displayName
    }
}

public enum VPNPath: Codable, Equatable, Sendable {
    case direct(interface: String)
    case vpn(service: VPNService)
    case unidentifiedTunnel(interface: String)
    case unavailable
}

public enum VPNConnectivityFailure: Error, Codable, Equatable, Sendable {
    case dnsResolutionFailed
    case noRoute
    case routeDoesNotUseConnectedVPN(activeServices: [VPNService])
    case targetDidNotRespond(path: VPNPath)
    case diagnosisUnavailable(String)
}

public struct VPNConnectivityDiagnosis: Codable, Equatable, Sendable {
    public let target: VPNTarget
    public let reachable: Bool
    public let path: VPNPath
    public let failure: VPNConnectivityFailure?
    public let checkedAt: Date

    public init(
        target: VPNTarget,
        reachable: Bool,
        path: VPNPath,
        failure: VPNConnectivityFailure?,
        checkedAt: Date
    ) {
        self.target = target
        self.reachable = reachable
        self.path = path
        self.failure = failure
        self.checkedAt = checkedAt
    }
}

public protocol VPNHostResolving: Sendable {
    func addresses(for host: String) async -> Result<[String], VPNConnectivityFailure>
}

public protocol VPNRouteResolving: Sendable {
    func interfaceName(to address: String) async -> Result<String, VPNConnectivityFailure>
}

public protocol VPNTCPProbing: Sendable {
    func canConnect(host: String, port: Int, timeoutSeconds: Double) async -> Bool
}

public protocol VPNConnectivityDiagnosing: Sendable {
    func diagnose(_ target: VPNTarget) async -> VPNConnectivityDiagnosis
}
