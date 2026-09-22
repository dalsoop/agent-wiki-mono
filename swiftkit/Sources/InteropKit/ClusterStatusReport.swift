import Foundation

/// 3-Tier 빌드 클러스터 상태 보고서 구조체 (`app-build-manager cluster status --json`).
public struct ClusterStatusReport: Codable, Equatable, Sendable {
    public struct CurrentHost: Codable, Equatable, Sendable {
        public let name: String
        public let role: String
        public let localHostName: String

        public init(name: String, role: String, localHostName: String) {
            self.name = name
            self.role = role
            self.localHostName = localHostName
        }
    }

    public struct ThisMac: Codable, Equatable, Sendable {
        public let role: String
        public let status: String?
        public let isCurrentHost: Bool?
        public let hardware: String
        public let cores: Int
        public let compileCap: String
        public let offloadEnabled: Bool
        public let targetHost: String
        public let configFile: String

        public init(
            role: String = "Local Builder",
            status: String? = nil,
            isCurrentHost: Bool? = nil,
            hardware: String,
            cores: Int,
            compileCap: String,
            offloadEnabled: Bool,
            targetHost: String,
            configFile: String
        ) {
            self.role = role
            self.status = status
            self.isCurrentHost = isCurrentHost
            self.hardware = hardware
            self.cores = cores
            self.compileCap = compileCap
            self.offloadEnabled = offloadEnabled
            self.targetHost = targetHost
            self.configFile = configFile
        }
    }

    public struct NextMac: Codable, Equatable, Sendable {
        public let role: String
        public let status: String?
        public let isCurrentHost: Bool?
        public let host: String
        public let sshReachable: Bool
        public let latencyMs: Double
        public let hardware: String
        public let cores: Int
        public let loadAverages: [Double]

        public init(
            role: String = "Workstation Worker",
            status: String? = nil,
            isCurrentHost: Bool? = nil,
            host: String,
            sshReachable: Bool,
            latencyMs: Double,
            hardware: String,
            cores: Int,
            loadAverages: [Double]
        ) {
            self.role = role
            self.status = status
            self.isCurrentHost = isCurrentHost
            self.host = host
            self.sshReachable = sshReachable
            self.latencyMs = latencyMs
            self.hardware = hardware
            self.cores = cores
            self.loadAverages = loadAverages
        }
    }

    public struct Server50: Codable, Equatable, Sendable {
        public let role: String
        public let host: String
        public let pingMs: Double
        public let casOnline: Bool
        public let ports: [String: Bool]
        public let disk: DiskInfo

        public init(
            role: String = "NativeLink CAS Hub",
            host: String,
            pingMs: Double,
            casOnline: Bool,
            ports: [String: Bool],
            disk: DiskInfo
        ) {
            self.role = role
            self.host = host
            self.pingMs = pingMs
            self.casOnline = casOnline
            self.ports = ports
            self.disk = disk
        }
    }

    public struct DiskInfo: Codable, Equatable, Sendable {
        public let filesystem: String
        public let total: String
        public let used: String
        public let available: String
        public let usePercentage: String

        public init(
            filesystem: String,
            total: String,
            used: String,
            available: String,
            usePercentage: String
        ) {
            self.filesystem = filesystem
            self.total = total
            self.used = used
            self.available = available
            self.usePercentage = usePercentage
        }
    }

    public struct ClusterPayload: Codable, Equatable, Sendable {
        public let currentHost: CurrentHost?
        public let thisMac: ThisMac
        public let nextMac: NextMac
        public let server50: Server50

        public init(
            currentHost: CurrentHost? = nil,
            thisMac: ThisMac,
            nextMac: NextMac,
            server50: Server50
        ) {
            self.currentHost = currentHost
            self.thisMac = thisMac
            self.nextMac = nextMac
            self.server50 = server50
        }
    }

    public let ok: Bool
    public let cluster: ClusterPayload

    public init(ok: Bool = true, cluster: ClusterPayload) {
        self.ok = ok
        self.cluster = cluster
    }
}
