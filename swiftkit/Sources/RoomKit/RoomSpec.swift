import Foundation
@_exported import RoomSeatKit
@_exported import RoomPlacementKit

/// 방의 예산 스냅샷
public struct RoomBudgetSnapshot: Codable, Equatable, Sendable {
    public var window: Int
    public var trigger: Double
    public var initialInput: Int
    public var reservedOutput: Int
    public var usable: Int
    public var handoffAt: Int

    public init(
        window: Int,
        trigger: Double,
        initialInput: Int,
        reservedOutput: Int,
        usable: Int,
        handoffAt: Int
    ) {
        self.window = window
        self.trigger = trigger
        self.initialInput = initialInput
        self.reservedOutput = reservedOutput
        self.usable = usable
        self.handoffAt = handoffAt
    }

    public static let zero = RoomBudgetSnapshot(
        window: 0,
        trigger: 0.0,
        initialInput: 0,
        reservedOutput: 0,
        usable: 0,
        handoffAt: 0
    )
}

/// 예산 국면. `budget --json` 과 빈병 JSON 의 `state` 값.
/// 2026-09-07 room-terminal 의 구현을 정본으로 흡수했다(room-single-model).
public enum BudgetPhase: String, Codable, Sendable, Equatable {
    case ok
    case handoffDue = "handoff-due"
    case over
    case unknown
}

/// 예산 상태 스냅샷 — `budget --json`, 핸드오프 요청·요약이 공유하는 상태.
/// 키·rawValue 레이아웃은 room-terminal 구현과 동일하다(옛 JSON 호환 골든 테스트로 증명).
public struct BudgetState: Codable, Equatable, Sendable {
    public var window: Int
    public var trigger: Double
    public var initialInput: Int
    public var reservedOutput: Int
    public var usable: Int
    public var used: Int?
    public var handoffAt: Int
    public var elapsedMinutes: Int?
    public var estimatedWorkMinutes: Int?
    public var state: BudgetPhase

    public init(
        window: Int,
        trigger: Double,
        initialInput: Int,
        reservedOutput: Int,
        usable: Int,
        used: Int?,
        handoffAt: Int,
        elapsedMinutes: Int?,
        estimatedWorkMinutes: Int?,
        state: BudgetPhase
    ) {
        self.window = window
        self.trigger = trigger
        self.initialInput = initialInput
        self.reservedOutput = reservedOutput
        self.usable = usable
        self.used = used
        self.handoffAt = handoffAt
        self.elapsedMinutes = elapsedMinutes
        self.estimatedWorkMinutes = estimatedWorkMinutes
        self.state = state
    }

    public var suggestsHandoff: Bool {
        state == .handoffDue || state == .over
    }

    public var remainder: Int {
        guard let used else { return usable }
        return usable - used
    }
}

/// 예산 국면 판정 순수 함수. 파일·프로세스 접근이 없다 — 사용량 읽기는 호출자의 몫이다.
public enum BudgetJudgment {
    public static func phase(
        used: Int?,
        usable: Int,
        handoffAt: Int,
        elapsedMinutes: Int?,
        estimatedWorkMinutes: Int?
    ) -> BudgetPhase {
        let timeDue = isTimeDue(
            elapsedMinutes: elapsedMinutes,
            estimatedWorkMinutes: estimatedWorkMinutes
        )
        guard let used else {
            return timeDue ? .handoffDue : .unknown
        }
        switch used {
        case usable...:
            return .over
        case handoffAt...:
            return .handoffDue
        default:
            return timeDue ? .handoffDue : .ok
        }
    }

    public static func isTimeDue(elapsedMinutes: Int?, estimatedWorkMinutes: Int?) -> Bool {
        guard let elapsed = elapsedMinutes,
              let estimated = estimatedWorkMinutes,
              estimated > 0 else { return false }
        return elapsed >= estimated * 3
    }
}

/// 방 실행 및 격리 통합 정책
public struct RoomExecutionPolicy: Codable, Equatable, Sendable {
    public var sandboxBackend: SandboxBackend
    public var windowPolicy: RoomWindowPolicy
    public var lineage: RoomLineage
    public var budget: RoomBudgetSnapshot

    public init(
        sandboxBackend: SandboxBackend = .seatbelt,
        windowPolicy: RoomWindowPolicy = .default,
        lineage: RoomLineage = RoomLineage(),
        budget: RoomBudgetSnapshot = .zero
    ) {
        self.sandboxBackend = sandboxBackend
        self.windowPolicy = windowPolicy
        self.lineage = lineage
        self.budget = budget
    }

    public static let `default` = RoomExecutionPolicy()
}

/// 방 계통 계보 (Lineage)
public struct RoomLineage: Codable, Equatable, Sendable {
    public var planID: String?
    public var blueprintSlug: String?
    public var parentRoomID: UUID?

    public init(
        planID: String? = nil,
        blueprintSlug: String? = nil,
        parentRoomID: UUID? = nil
    ) {
        self.planID = planID
        self.blueprintSlug = blueprintSlug
        self.parentRoomID = parentRoomID
    }
}

/// 방 격리 명세
public struct RoomSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { roomID }

    public var roomID: UUID
    public var tenantID: TenantID
    public var tenant: String {
        get { tenantID.slug }
        set { tenantID = TenantID(newValue) }
    }
    public var task: String
    public var verdict: String
    public var workdir: String?
    public var walls: RoomWalls
    public var launch: RoomLaunch?
    public var budget: RoomBudgetSnapshot
    public var lineage: RoomLineage
    /// 프로세스 격리 백엔드. 기본은 `seatbelt`. 기존 JSON 에 키가 없으면 seatbelt 로 디코딩된다.
    public var sandboxBackend: SandboxBackend
    /// 창(Window) 격리 정책. 기본은 가상 워크스페이스. 기존 JSON 에 키가 없으면 .default 로 디코딩된다.
    public var windowPolicy: RoomWindowPolicy

    public init(
        roomID: UUID = UUID(),
        tenantID: TenantID,
        task: String,
        verdict: String,
        workdir: String? = nil,
        walls: RoomWalls = RoomWalls(),
        launch: RoomLaunch? = nil,
        executionPolicy: RoomExecutionPolicy = .default
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.task = task
        self.verdict = verdict
        self.workdir = workdir
        self.walls = walls
        self.launch = launch
        self.budget = executionPolicy.budget
        self.lineage = executionPolicy.lineage
        self.sandboxBackend = executionPolicy.sandboxBackend
        self.windowPolicy = executionPolicy.windowPolicy
    }

    public init(
        roomID: UUID = UUID(),
        tenant: String,
        task: String,
        verdict: String,
        workdir: String? = nil,
        walls: RoomWalls = RoomWalls(),
        launch: RoomLaunch? = nil,
        executionPolicy: RoomExecutionPolicy = .default
    ) {
        self.init(
            roomID: roomID,
            tenantID: TenantID(tenant),
            task: task,
            verdict: verdict,
            workdir: workdir,
            walls: walls,
            launch: launch,
            executionPolicy: executionPolicy
        )
    }

    // MARK: - Codable (기존 JSON 호환: tenant 및 tenantID 상호 복원, sandboxBackend 및 windowPolicy 부재 시 기본값)

    enum CodingKeys: String, CodingKey {
        case roomID, tenant, tenantID, task, verdict, workdir, walls, launch, budget, lineage, sandboxBackend, windowPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = try container.decode(UUID.self, forKey: .roomID)
        if let directTenantID = try container.decodeIfPresent(TenantID.self, forKey: .tenantID) {
            tenantID = directTenantID
        } else if let tenantStr = try container.decodeIfPresent(String.self, forKey: .tenant) {
            tenantID = TenantID(tenantStr)
        } else {
            tenantID = .default
        }
        task = try container.decode(String.self, forKey: .task)
        verdict = try container.decode(String.self, forKey: .verdict)
        workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        walls = try container.decode(RoomWalls.self, forKey: .walls)
        launch = try container.decodeIfPresent(RoomLaunch.self, forKey: .launch)
        budget = try container.decodeIfPresent(RoomBudgetSnapshot.self, forKey: .budget) ?? .zero
        lineage = try container.decodeIfPresent(RoomLineage.self, forKey: .lineage) ?? RoomLineage()
        sandboxBackend = try container.decodeIfPresent(SandboxBackend.self, forKey: .sandboxBackend) ?? .seatbelt
        windowPolicy = try container.decodeIfPresent(RoomWindowPolicy.self, forKey: .windowPolicy) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(tenantID.slug, forKey: .tenant)
        try container.encode(tenantID, forKey: .tenantID)
        try container.encode(task, forKey: .task)
        try container.encode(verdict, forKey: .verdict)
        try container.encodeIfPresent(workdir, forKey: .workdir)
        try container.encode(walls, forKey: .walls)
        try container.encodeIfPresent(launch, forKey: .launch)
        try container.encode(budget, forKey: .budget)
        try container.encode(lineage, forKey: .lineage)
        try container.encode(sandboxBackend, forKey: .sandboxBackend)
        try container.encode(windowPolicy, forKey: .windowPolicy)
    }
}

