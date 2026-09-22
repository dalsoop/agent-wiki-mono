import Foundation

/// 워크트리 분기 및 체크아웃 전략.
/// 대규모 모노레포 환경에서 불필요한 전체 체크아웃 I/O 비용을 제거하기 위한 모델.
public enum WorktreeStrategy: Sendable, Equatable {
    /// 기본 전체 체크아웃: `git worktree add [-b <branch>] <path> [<baseRef>]`
    case standard

    /// 파일 미체크아웃: 메타데이터만 즉시 생성 (`--no-checkout`).
    /// 빌드 캐시나 특정 파일만 필요하거나, 이후 sparse-checkout을 적용할 때 사용.
    case noCheckout

    /// 희소 체크아웃: 모노레포의 특정 하위 디렉터리/파일만 선택적으로 체크아웃.
    /// `--no-checkout` 생성 후 `git sparse-checkout set` 실행.
    case sparseCheckout(paths: [String], cone: Bool = true)

    /// APFS Copy-on-Write (clonefile / cp -c) 기반 분기:
    /// 기존 웜 워크트리(예: `.worktrees/main`)의 파일 트리를 CoW로 즉시 복제하고 git 인덱스 동기화.
    case apfsCoW(sourceWorktreePath: String)
}

/// 고속 워크트리 생성 및 재사용 요청.
public struct FastWorktreeRequest: Sendable, Equatable {
    /// Git 저장소 경로 (bare 저장소 또는 `.git`이 위치한 루트 경로).
    public let repoPath: String

    /// 생성하거나 재사용할 대상 워크트리 디렉터리 경로.
    public let targetPath: String

    /// 체크아웃 또는 생성할 브랜치명.
    public let branch: String

    /// 기준 커밋/브랜치 (예: "origin/main", nil인 경우 기본 HEAD 사용).
    public let baseRef: String?

    /// 브랜치 생성 여부 (`-b` 플래그 적용 여부). 기본값 true.
    public let createBranch: Bool

    /// 분리 헤드(detached HEAD) 여부 (`--detach` 플래그 적용 여부). 기본값 false.
    public let detach: Bool

    /// 워크트리 생성 전략.
    public let strategy: WorktreeStrategy

    /// 대상 경로가 이미 연결된 워크트리(.git 파일 존재)인 경우 재사용 여부. 기본값 true (0ms 즉시 반환).
    public let reuseIfLinked: Bool

    /// 생성 완료 후 push.autoSetupRemote 설정 적용 여부. 기본값 true.
    public let autoSetupRemote: Bool

    /// 동시성 락 획득 타임아웃(초). 기본값 30초.
    public let lockTimeout: TimeInterval

    /// 락 경합 발생 시 최대 재시도 횟수. 기본값 5회.
    public let maxRetries: Int

    /// 재시도 기본 대기 시간(초). 지수 백오프 적용. 기본값 0.05초.
    public let retryBaseDelay: TimeInterval

    public init(
        repoPath: String,
        targetPath: String,
        branch: String = "",
        baseRef: String? = nil,
        createBranch: Bool = true,
        detach: Bool = false,
        strategy: WorktreeStrategy = .standard,
        reuseIfLinked: Bool = true,
        autoSetupRemote: Bool = true,
        lockTimeout: TimeInterval = 30.0,
        maxRetries: Int = 5,
        retryBaseDelay: TimeInterval = 0.05
    ) {
        self.repoPath = repoPath
        self.targetPath = targetPath
        self.branch = branch
        self.baseRef = baseRef
        self.createBranch = createBranch
        self.detach = detach
        self.strategy = strategy
        self.reuseIfLinked = reuseIfLinked
        self.autoSetupRemote = autoSetupRemote
        self.lockTimeout = lockTimeout
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
    }
}

/// 고속 워크트리 생성 및 재사용 결과.
public struct FastWorktreeResult: Sendable, Equatable {
    /// 워크트리 디렉터리 절대 경로.
    public let path: String

    /// 워크트리의 브랜치명.
    public let branch: String

    /// 기존 워크트리를 0ms로 즉각 재사용했는지 여부.
    public let reusedExisting: Bool

    /// 적용된 분기/체크아웃 전략.
    public let strategyUsed: WorktreeStrategy

    /// 작업 소요 시간(밀리초). 재사용 시 0.0ms.
    public let durationMs: Double

    /// 워크트리가 참조하는 실제 gitdir 경로 (예: `.../.bare/worktrees/main1`).
    public let gitDir: String?

    /// 추가 상태 또는 상세 메시지.
    public let details: String?

    public init(
        path: String,
        branch: String,
        reusedExisting: Bool,
        strategyUsed: WorktreeStrategy,
        durationMs: Double,
        gitDir: String? = nil,
        details: String? = nil
    ) {
        self.path = path
        self.branch = branch
        self.reusedExisting = reusedExisting
        self.strategyUsed = strategyUsed
        self.durationMs = durationMs
        self.gitDir = gitDir
        self.details = details
    }
}

/// 연결된 워크트리의 파일시스템 메타데이터.
public struct LinkedWorktreeInfo: Sendable, Equatable {
    /// 워크트리 루트 경로.
    public let path: String

    /// `.git` 파일이 가리키는 gitdir 실제 경로.
    public let gitDir: String

    /// `HEAD` 파일로부터 해석된 브랜치명 (예: `main`, `feat/x`). detached인 경우 nil.
    public let branch: String?

    /// `HEAD`가 가리키는 커밋 SHA (detached이거나 확인 가능한 경우).
    public let headCommit: String?

    public init(path: String, gitDir: String, branch: String?, headCommit: String? = nil) {
        self.path = path
        self.gitDir = gitDir
        self.branch = branch
        self.headCommit = headCommit
    }
}

/// 고속 워크트리 엔진 에러 정의.
public enum FastWorktreeError: Error, Sendable, Equatable, LocalizedError {
    case invalidPath(String)
    case lockTimeout(lockPath: String, timeout: TimeInterval)
    case exhaustedRetries(attempts: Int, lastError: String)
    case gitCommandFailed(command: String, exitCode: Int32, stderr: String)
    case apfsCoWFailed(source: String, destination: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "유효하지 않은 워크트리 경로: \(path)"
        case .lockTimeout(let lockPath, let timeout):
            return "워크트리 락 획득 타임아웃 (\(timeout)초 초과): \(lockPath)"
        case .exhaustedRetries(let attempts, let lastError):
            return "워크트리 생성 재시도 횟수 초과 (\(attempts)회): \(lastError)"
        case .gitCommandFailed(let cmd, let code, let stderr):
            return "git 명령 실패 (\(cmd), exitCode: \(code)): \(stderr)"
        case .apfsCoWFailed(let src, let dst, let reason):
            return "APFS Copy-on-Write 복제 실패 (\(src) -> \(dst)): \(reason)"
        }
    }
}
