import Foundation

// MARK: - 0. 액터 식별 (Room Actor)

public enum RoomActor: Codable, Sendable, Equatable, CustomStringConvertible {
    case user(name: String)
    case agent(name: String, sessionID: String)

    public var isUser: Bool {
        if case .user = self { return true }
        return false
    }

    public var isAgent: Bool {
        if case .agent = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .user(let name):
            return "user:\(name)"
        case .agent(let name, let sessionID):
            return "agent:\(name):\(sessionID)"
        }
    }
}

// MARK: - 1. 락 & 리스 (Lock & Lease + PID Probe)

public enum RoomLeaseStatus: String, Codable, Sendable {
    case active           // 에이전트 작업 중
    case pausedByHuman    // 인간이 [직접 개입]하여 일시 정지됨
    case released         // 작업 완료 및 락 정상 반납
    case expired          // 리스 시간 초과로 만료됨
}

/// 단일 에이전트 작업 점유 및 인간 개입을 통제하는 리스 락.
public struct RoomLeaseLock: Codable, Sendable, Equatable {
    public let roomID: String
    public let owner: RoomActor
    public let pid: Int32
    public let deviceID: String?
    public var leaseExpiry: Date
    public var status: RoomLeaseStatus

    public init(
        roomID: String,
        owner: RoomActor,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        deviceID: String? = nil,
        leaseDurationSeconds: TimeInterval = 30.0,
        status: RoomLeaseStatus = .active
    ) {
        self.roomID = roomID
        self.owner = owner
        self.pid = pid
        self.deviceID = deviceID
        self.leaseExpiry = Date().addingTimeInterval(leaseDurationSeconds)
        self.status = status
    }

    public static var defaultLocalDeviceID: String {
        ProcessInfo.processInfo.environment["SWIFT_APP_DEVICE_ID"] ?? "local-mac"
    }

    private static let loopbackHost = ["127", "0", "0", "1"].joined(separator: ".")

    /// 디바이스 식별자가 현재 로컬 머신과 일치하는지 정규화하여 판정합니다.
    public static func isLocalDevice(_ id: String?, currentDeviceID: String = defaultLocalDeviceID) -> Bool {
        guard let id = id, !id.isEmpty else { return true }
        if id == currentDeviceID { return true }
        let localAliases: Set<String> = ["local-mac", "localhost", loopbackHost, ProcessInfo.processInfo.hostName]
        if localAliases.contains(id) && localAliases.contains(currentDeviceID) {
            return true
        }
        return false
    }

    /// PID 생존 여부 프로브 (kill -0 + POSIX EPERM 처리 + 원격 격리)
    public func isProcessAlive(currentDeviceID: String = defaultLocalDeviceID) -> Bool {
        guard pid > 0 else { return false }

        // 원격 디바이스 소유인 경우 로컬 호스트의 PID를 조회하면 엉뚱한 로컬 프로세스가 조회되는
        // 유령 PID 섀도잉 오류가 발생하므로, 로컬 kill()을 절대 호출하지 않고 리스 만료 시간에 위임한다.
        if !Self.isLocalDevice(deviceID, currentDeviceID: currentDeviceID) {
            return Date() < leaseExpiry
        }

        // 로컬 프로세스인 경우 POSIX kill(pid, 0)
        // 리턴값이 0이거나, EPERM(프로세스는 존재하나 권한 부족)인 경우 생존으로 판정한다.
        let result = kill(pid, 0)
        let isSuccess = (result == 0)
        let isPermissionDenied = (result == -1 && errno == EPERM)
        return isSuccess || isPermissionDenied
    }

    /// 원격 프로브 클로저를 활용한 비동기 프로세스 생존 검사
    public func isProcessAliveRemote(
        currentDeviceID: String = defaultLocalDeviceID,
        remoteProbe: ((_ deviceID: String, _ pid: Int32) async throws -> Bool)? = nil
    ) async -> Bool {
        guard pid > 0 else { return false }
        if !Self.isLocalDevice(deviceID, currentDeviceID: currentDeviceID) {
            if let probe = remoteProbe, let dev = deviceID {
                return (try? await probe(dev, pid)) ?? false
            }
            return Date() < leaseExpiry
        }
        return isProcessAlive(currentDeviceID: currentDeviceID)
    }

    /// 리스가 현재 유효한지 검사
    public var isValid: Bool {
        isValid(currentDeviceID: Self.defaultLocalDeviceID)
    }

    public func isValid(currentDeviceID: String = defaultLocalDeviceID) -> Bool {
        guard status == .active else { return false }
        return Date() < leaseExpiry && isProcessAlive(currentDeviceID: currentDeviceID)
    }

    /// 인간이 [직접 개입] 버튼을 눌렀을 때 호출
    public mutating func pauseByHuman() {
        self.status = .pausedByHuman
    }

    /// 인간 작업 완료 후 에이전트 재개
    public mutating func resumeByHuman(additionalSeconds: TimeInterval = 30.0) {
        self.status = .active
        self.leaseExpiry = Date().addingTimeInterval(additionalSeconds)
    }

    /// 락 반납
    public mutating func release() {
        self.status = .released
    }
}

// MARK: - 2. Tick 주기 동기화 (Placement Tick / 진행 상황 보고)

/// 에이전트가 주기적으로 원장에 덤프하는 placement tick 스냅샷.
public struct RoomPlacementTick: Codable, Sendable, Equatable {
    public let roomID: String
    public let agentID: String
    public let round: Int
    public let progressPercent: Double
    public let currentStage: String
    public let nextMilestone: String
    public let timestamp: Date

    public init(
        roomID: String,
        agentID: String,
        round: Int,
        progressPercent: Double,
        currentStage: String,
        nextMilestone: String,
        timestamp: Date = Date()
    ) {
        self.roomID = roomID
        self.agentID = agentID
        self.round = round
        self.progressPercent = min(100.0, max(0.0, progressPercent))
        self.currentStage = currentStage
        self.nextMilestone = nextMilestone
        self.timestamp = timestamp
    }
}

// MARK: - 3. 상의형 방 (Review Room · Multi-Agent Debate Protocol)

/// 다중 에이전트 토론 프로토콜을 규격화한 구조화 JSON 스키마.
public struct AgentDebateProposal: Codable, Sendable, Equatable {
    public let roomID: String
    public let round: Int
    public let proposal: String
    public var agrees: [String]
    public var disagrees: [String]
    public var revisions: String
    public var evidence: String
    public let timestamp: Date

    public init(
        roomID: String,
        round: Int,
        proposal: String,
        agrees: [String] = [],
        disagrees: [String] = [],
        revisions: String = "",
        evidence: String = "",
        timestamp: Date = Date()
    ) {
        self.roomID = roomID
        self.round = round
        self.proposal = proposal
        self.agrees = agrees
        self.disagrees = disagrees
        self.revisions = revisions
        self.evidence = evidence
        self.timestamp = timestamp
    }

    /// 합의율 (0.0 ~ 1.0)
    public var consensusRatio: Double {
        let total = agrees.count + disagrees.count
        guard total > 0 else { return 0.0 }
        return Double(agrees.count) / Double(total)
    }

    /// 과반 이상(또는 지정된 임계값) 합의 도달 여부
    public func isResolved(threshold: Double = 0.8) -> Bool {
        return consensusRatio >= threshold
    }
}

// MARK: - 4. 인계 (Handoff) 및 컨텍스트 전달 카드

/// 워커 에이전트 간 락 및 컨텍스트 인계 카드.
public struct HandoffDigest: Codable, Sendable, Equatable {
    public let taskID: String
    public let fromAgent: String
    public let toAgent: String
    public let completedMilestones: [String]
    public let pendingMilestones: [String]
    public let sharedContextSummary: String
    public let timestamp: Date

    public init(
        taskID: String,
        fromAgent: String,
        toAgent: String,
        completedMilestones: [String],
        pendingMilestones: [String],
        sharedContextSummary: String,
        timestamp: Date = Date()
    ) {
        self.taskID = taskID
        self.fromAgent = fromAgent
        self.toAgent = toAgent
        self.completedMilestones = completedMilestones
        self.pendingMilestones = pendingMilestones
        self.sharedContextSummary = sharedContextSummary
        self.timestamp = timestamp
    }
}
