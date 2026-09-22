import Foundation

public enum EmulatorType: String, Codable, CaseIterable, Sendable {
    case android
    case browser
    case desktop
    case macos
    case wearos
    case windows
}

public enum FleetPowerState: String, Codable, Sendable {
    case running
    case stopped
    case unknown
}

public struct FleetInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let type: EmulatorType
    public let release: String
    public let host: String?
    public let power: FleetPowerState
    public let ready: Bool
    /// 서버가 관측한 준비 상태의 근거. 구형 서버 응답에는 없을 수 있다.
    public let readinessReason: String?
    public let node: String?
    public let desiredReplicas: Int
    public let managementKind: String
    public let pvcs: [String]
    public let operationId: String?

    public struct Identity: Codable, Equatable, Sendable {
        public var name: String
        public var type: EmulatorType
        public var release: String
        public var host: String?
        public init(
            name: String,
            type: EmulatorType,
            release: String,
            host: String? = nil
        ) {
            self.name = name
            self.type = type
            self.release = release
            self.host = host
        }
    }

    public struct Power: Codable, Equatable, Sendable {
        public var power: FleetPowerState
        public var ready: Bool
        public var readinessReason: String?
        public var node: String?
        public init(
            power: FleetPowerState,
            ready: Bool,
            readinessReason: String? = nil,
            node: String? = nil
        ) {
            self.power = power
            self.ready = ready
            self.readinessReason = readinessReason
            self.node = node
        }
    }

    public struct Management: Codable, Equatable, Sendable {
        public var desiredReplicas: Int
        public var managementKind: String
        public var pvcs: [String]
        public var operationId: String?
        public init(
            desiredReplicas: Int,
            managementKind: String,
            pvcs: [String] = [],
            operationId: String? = nil
        ) {
            self.desiredReplicas = desiredReplicas
            self.managementKind = managementKind
            self.pvcs = pvcs
            self.operationId = operationId
        }
    }

    public init(identity: Identity, power: Power, management: Management) {
        self.name = identity.name
        self.type = identity.type
        self.release = identity.release
        self.host = identity.host
        self.power = power.power
        self.ready = power.ready
        self.readinessReason = power.readinessReason
        self.node = power.node
        self.desiredReplicas = management.desiredReplicas
        self.managementKind = management.managementKind
        self.pvcs = management.pvcs
        self.operationId = management.operationId
    }
}

public struct RetainedPVC: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let phase: String?
    public let capacity: String?

    public init(name: String, phase: String? = nil, capacity: String? = nil) {
        self.name = name
        self.phase = phase
        self.capacity = capacity
    }
}

public struct RetainedFleetInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let type: EmulatorType
    public let pvcs: [RetainedPVC]

    public init(name: String, type: EmulatorType, pvcs: [RetainedPVC]) {
        self.name = name
        self.type = type
        self.pvcs = pvcs
    }
}

public enum LifecycleAction: String, Codable, Sendable {
    case start
    case restart
    case stop
}

public struct FleetOperation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let instanceName: String
    public let stage: String
    public let status: String
    public let error: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        kind: String,
        instanceName: String,
        stage: String,
        status: String,
        error: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.instanceName = instanceName
        self.stage = stage
        self.status = status
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Execution effort accepted by the desktop agent worker. The control API fixes
/// the worker and model; clients may only select this bounded execution level.
public enum FleetAgentJobEffort: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case xhigh
}

public struct FleetAgentJobRequest: Codable, Equatable, Sendable {
    public let title: String
    public let prompt: String
    public let workdir: String?
    public let effort: FleetAgentJobEffort
    public let timeoutMinutes: Int

    public init(
        title: String,
        prompt: String,
        workdir: String? = nil,
        effort: FleetAgentJobEffort = .medium,
        timeoutMinutes: Int = 20
    ) {
        self.title = title
        self.prompt = prompt
        self.workdir = workdir
        self.effort = effort
        self.timeoutMinutes = timeoutMinutes
    }
}

public struct FleetAgentJobSpec: Codable, Equatable, Sendable {
    public let title: String
    public let prompt: String
    public let workdir: String
    public let worker: String
    public let model: String
    public let effort: FleetAgentJobEffort
    public let timeoutMinutes: Int
    public let isolation: String
    public let allowedPaths: [String]
    public let forbiddenPaths: [String]

    public struct Prompt: Codable, Equatable, Sendable {
        public var title: String
        public var prompt: String
        public var workdir: String
        public init(title: String, prompt: String, workdir: String) {
            self.title = title
            self.prompt = prompt
            self.workdir = workdir
        }
    }

    public struct Worker: Codable, Equatable, Sendable {
        public var worker: String
        public var model: String
        public var effort: FleetAgentJobEffort
        public var timeoutMinutes: Int
        public init(
            worker: String,
            model: String,
            effort: FleetAgentJobEffort,
            timeoutMinutes: Int
        ) {
            self.worker = worker
            self.model = model
            self.effort = effort
            self.timeoutMinutes = timeoutMinutes
        }
    }

    public struct Isolation: Codable, Equatable, Sendable {
        public var isolation: String
        public var allowedPaths: [String]
        public var forbiddenPaths: [String]
        public init(
            isolation: String,
            allowedPaths: [String] = [],
            forbiddenPaths: [String] = []
        ) {
            self.isolation = isolation
            self.allowedPaths = allowedPaths
            self.forbiddenPaths = forbiddenPaths
        }
    }

    public init(prompt: Prompt, worker: Worker, isolation: Isolation) {
        self.title = prompt.title
        self.prompt = prompt.prompt
        self.workdir = prompt.workdir
        self.worker = worker.worker
        self.model = worker.model
        self.effort = worker.effort
        self.timeoutMinutes = worker.timeoutMinutes
        self.isolation = isolation.isolation
        self.allowedPaths = isolation.allowedPaths
        self.forbiddenPaths = isolation.forbiddenPaths
    }
}

public struct FleetAgentJob: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let state: String
    public let spec: FleetAgentJobSpec
    public let failureMessage: String?
    public let workerExitCode: Int?
    public let scopeViolations: [String]
    public let changedFiles: [String]
    public let createdAt: Date?
    public let startedAt: Date?
    public let endedAt: Date?

    public struct Result: Codable, Equatable, Sendable {
        public var failureMessage: String?
        public var workerExitCode: Int?
        public var scopeViolations: [String]
        public var changedFiles: [String]
        public init(
            failureMessage: String? = nil,
            workerExitCode: Int? = nil,
            scopeViolations: [String] = [],
            changedFiles: [String] = []
        ) {
            self.failureMessage = failureMessage
            self.workerExitCode = workerExitCode
            self.scopeViolations = scopeViolations
            self.changedFiles = changedFiles
        }
    }

    public struct Timing: Codable, Equatable, Sendable {
        public var createdAt: Date?
        public var startedAt: Date?
        public var endedAt: Date?
        public init(
            createdAt: Date? = nil,
            startedAt: Date? = nil,
            endedAt: Date? = nil
        ) {
            self.createdAt = createdAt
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }

    public init(
        id: String,
        state: String,
        spec: FleetAgentJobSpec,
        result: Result = Result(),
        timing: Timing = Timing()
    ) {
        self.id = id
        self.state = state
        self.spec = spec
        self.failureMessage = result.failureMessage
        self.workerExitCode = result.workerExitCode
        self.scopeViolations = result.scopeViolations
        self.changedFiles = result.changedFiles
        self.createdAt = timing.createdAt
        self.startedAt = timing.startedAt
        self.endedAt = timing.endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, spec, failureMessage, workerExitCode
        case scopeViolations, changedFiles, createdAt, startedAt, endedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            state: try container.decode(String.self, forKey: .state),
            spec: try container.decode(FleetAgentJobSpec.self, forKey: .spec),
            result: Result(
                failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
                workerExitCode: try container.decodeIfPresent(Int.self, forKey: .workerExitCode),
                scopeViolations: try container.decodeIfPresent([String].self, forKey: .scopeViolations) ?? [],
                changedFiles: try container.decodeIfPresent([String].self, forKey: .changedFiles) ?? []
            ),
            timing: Timing(
                createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
                startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
                endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
            )
        )
    }
}

public struct FleetAgentJobDispatch: Codable, Equatable, Sendable {
    public let operation: FleetOperation
    public let job: FleetAgentJob?

    public init(operation: FleetOperation, job: FleetAgentJob?) {
        self.operation = operation
        self.job = job
    }
}

public struct FleetConsole: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let type: EmulatorType
    public let url: URL
    public let mode: String
    public let readiness: String
    /// 콘솔을 열 수 없을 때의 서버 관측 근거. 구형 서버 응답에는 없을 수 있다.
    public let readinessReason: String?
    public let capabilities: [String]

    public init(
        name: String,
        type: EmulatorType,
        url: URL,
        mode: String,
        readiness: String,
        readinessReason: String? = nil,
        capabilities: [String]
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.mode = mode
        self.readiness = readiness
        self.readinessReason = readinessReason
        self.capabilities = capabilities
    }
}

public struct PairingSession: Equatable, Sendable {
    public let expiresAt: Date

    public init(expiresAt: Date) {
        self.expiresAt = expiresAt
    }
}

public struct PairingCode: Codable, Equatable, Sendable {
    public let code: String
    public let expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

public enum EmulatorControlError: Error, Equatable, Sendable, CustomStringConvertible {
    case notPaired
    case unauthorized
    case invalidResponse
    case httpStatus(Int)

    public var description: String {
        switch self {
        case .notPaired:
            "This device is not paired."
        case .unauthorized:
            "The device authorization is no longer valid."
        case .invalidResponse:
            "The emulator control service returned an invalid response."
        case let .httpStatus(status):
            "The emulator control service returned HTTP \(status)."
        }
    }
}
