import Foundation

/// 빌드 클러스터(이 맥·옆 맥) 상태 보고서 구조체 (`app-build-manager cluster status --json`).
/// 50서버(NativeLink 허브)는 2026-09-25 폐기했다.
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

    public struct ClusterPayload: Codable, Equatable, Sendable {
        public let currentHost: CurrentHost?
        public let thisMac: ThisMac
        public let nextMac: NextMac

        public init(
            currentHost: CurrentHost? = nil,
            thisMac: ThisMac,
            nextMac: NextMac
        ) {
            self.currentHost = currentHost
            self.thisMac = thisMac
            self.nextMac = nextMac
        }
    }

    public let ok: Bool
    public let cluster: ClusterPayload

    public init(ok: Bool = true, cluster: ClusterPayload) {
        self.ok = ok
        self.cluster = cluster
    }
}
