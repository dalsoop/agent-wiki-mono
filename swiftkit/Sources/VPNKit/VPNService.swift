public enum VPNServiceStatus: String, Codable, Equatable, Sendable {
    case connected, disconnected, connecting, disconnecting, invalid
}

public struct VPNService: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let providerBundleID: String
    public let status: VPNServiceStatus
    public let interfaceName: String?

    public var isConnected: Bool { status == .connected }
}

public struct VPNServiceReference: Codable, Equatable, Sendable {
    public let serviceID: String?
    public let displayName: String
    public let legacyIdentifier: String?

    public init(serviceID: String?, displayName: String, legacyIdentifier: String? = nil) {
        self.serviceID = serviceID
        self.displayName = displayName
        self.legacyIdentifier = legacyIdentifier
    }

    public static func legacy(_ value: String) -> Self {
        .init(serviceID: nil, displayName: value, legacyIdentifier: value)
    }
}
