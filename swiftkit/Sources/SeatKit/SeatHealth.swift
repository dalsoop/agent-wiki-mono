import Foundation

/// 자리 하나의 성한 상태 — 점유자가 실재하나, 작업 경로가 실재하나.
///
/// 판정은 `Employment.check(_:)`(고용 앱)이 하고, 이 타입은 그 **결과의 어휘**만 진다.
/// 판정기를 여기 두지 않는 건 의도다: 자리를 *보기만* 하는 앱(예: Agent Apps Bar)은
/// worktree·프로세스를 뒤질 권한도 이유도 없으면서 결과는 읽어야 하기 때문이다.
public struct SeatHealth: Sendable, Equatable {
    public var handle: String
    public var occupantAvailable: Bool
    public var workspaceExists: Bool
    public var issues: [String]
    public var ok: Bool { issues.isEmpty }

    public init(
        handle: String,
        occupantAvailable: Bool,
        workspaceExists: Bool,
        issues: [String]
    ) {
        self.handle = handle
        self.occupantAvailable = occupantAvailable
        self.workspaceExists = workspaceExists
        self.issues = issues
    }
}

/// `ps` 보드 한 줄 — 자리를 한 눈에 늘어놓을 때의 납작한 표현.
public struct SeatBoardRow: Sendable, Equatable, Identifiable {
    public var handle: String
    public var occupant: String
    public var kind: String
    public var tenant: String?
    public var workdir: String?
    public var workspaceKind: String
    public var healthOK: Bool
    public var issues: [String]
    /// 다른 자리와 작업 경로를 겹쳐 쓰고 있다 — 겹치면 서로의 변경을 밟는다.
    public var sharedPath: Bool
    public var sharedWith: [String]
    public var id: String { handle }

    public init(
        handle: String,
        occupant: String,
        kind: String,
        tenant: String?,
        workdir: String?,
        workspaceKind: String,
        healthOK: Bool,
        issues: [String],
        sharedPath: Bool,
        sharedWith: [String]
    ) {
        self.handle = handle
        self.occupant = occupant
        self.kind = kind
        self.tenant = tenant
        self.workdir = workdir
        self.workspaceKind = workspaceKind
        self.healthOK = healthOK
        self.issues = issues
        self.sharedPath = sharedPath
        self.sharedWith = sharedWith
    }
}
