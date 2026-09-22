import Foundation
import CommandKit

/// 대규모 모노레포를 지원하는 고속 워크트리 엔진.
///
/// 핵심 설계:
/// 1. `isLinkedWorktree` 0ms 즉각 반환: 이미 연결된 워크트리(.git 파일 존재)인 경우 Git 프로세스 호출 없이 재사용.
/// 2. 모노레포 워크트리 고속 생성 최적화:
///    - `--no-checkout`: 전체 체크아웃 없이 메타데이터만 즉시 생성.
///    - `sparse-checkout`: 필요한 서브 패키지/앱만 선택적 체크아웃.
///    - APFS Copy-on-Write (clonefile): 웜 워크트리의 소스 트리를 CoW로 무비용 복제.
/// 3. Git `index.lock` 및 동시성 경합 방지:
///    - 프로세스 간 advisory flock 파일 락 및 프로세스 내 직렬화.
///    - Git 락 경합 시 지수 백오프 + 지터 자동 재시도.
public struct FastWorktreeEngine: Sendable {
    public let runner: any CommandRunning
    public let gitPath: String
    public let lockCoordinator: WorktreeLockCoordinator

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        gitPath: String = "/usr/bin/git",
        lockCoordinator: WorktreeLockCoordinator = WorktreeLockCoordinator()
    ) {
        self.runner = runner
        self.gitPath = gitPath
        self.lockCoordinator = lockCoordinator
    }

    // MARK: - 연결된 워크트리 판별 (0ms 판정)

    /// 주어진 경로가 이미 연결된 워크트리인지 파일시스템 레벨에서 판별 (0ms).
    ///
    /// 원리:
    /// - 기본 Git 저장소는 `.git`이 **디렉터리**임.
    /// - `git worktree add`로 생성된 연결 워크트리는 `.git`이 **일반 텍스트 파일**이며,
    ///   내용이 `gitdir: <경로>`로 시작함.
    public static func isLinkedWorktree(at path: String, fileManager: FileManager = .default) -> Bool {
        let dotGitPath: String
        var isDir: ObjCBool = false

        if fileManager.fileExists(atPath: path, isDirectory: &isDir) {
            if isDir.boolValue {
                dotGitPath = (path as NSString).appendingPathComponent(".git")
            } else {
                // path 자체가 .git 파일인 경우
                dotGitPath = path
            }
        } else {
            return false
        }

        var gitIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGitPath, isDirectory: &gitIsDir), !gitIsDir.boolValue else {
            return false
        }

        guard let content = try? String(contentsOfFile: dotGitPath, encoding: .utf8) else {
            return false
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("gitdir:")
    }

    /// URL 기반 `isLinkedWorktree` 편의 오버로드.
    public static func isLinkedWorktree(at url: URL, fileManager: FileManager = .default) -> Bool {
        isLinkedWorktree(at: url.path, fileManager: fileManager)
    }

    /// 현재 작업 디렉터리가 이미 연결된 워크트리인지 즉시 판별.
    public static func isCurrentDirectoryLinkedWorktree(fileManager: FileManager = .default) -> Bool {
        isLinkedWorktree(at: fileManager.currentDirectoryPath, fileManager: fileManager)
    }

    /// 모노레포 표준 동기 인프로세스 워크트리 확정/생성 API.
    /// 이미 연결된 워크트리가 존재하면 0ms로 즉시 반환하고, 부재 시 git 워크트리를 안전하게 생성합니다.
    public static func ensureWorktree(
        repo: String,
        name: String,
        targetPath: String? = nil,
        baseRef: String = "origin/main",
        gitPath: String = "/usr/bin/git",
        runner: ((_ args: [String]) throws -> String)? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        let targetDir = targetPath ?? (repo as NSString).appendingPathComponent(".worktrees/\(name)")
        if fileManager.fileExists(atPath: targetDir) && isLinkedWorktree(at: targetDir, fileManager: fileManager) {
            return targetDir
        }

        if let customRunner = runner {
            _ = try customRunner(["worktree", "add", "-b", name, targetDir, baseRef])
            return targetDir
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["-C", repo, "worktree", "add", "-b", name, targetDir, baseRef]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let (_, errData) = ProcessWait.untilExit(process, stdout: stdout, stderr: stderr, seconds: 30)

        guard process.terminationStatus == 0 else {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw FastWorktreeError.gitCommandFailed(
                command: "\(gitPath) -C \(repo) worktree add -b \(name) \(targetDir) \(baseRef)",
                exitCode: process.terminationStatus,
                stderr: err
            )
        }
        return targetDir
    }

    private static func resolveGitDirPath(raw: String, basePath: String) -> String {
        guard !raw.hasPrefix("/") else { return raw }
        return URL(fileURLWithPath: basePath).appendingPathComponent(raw).standardized.path
    }

    private static func parseHeadBranchAndCommit(at gitDir: String) -> (branch: String?, headCommit: String?) {
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        let headContent: String
        do {
            headContent = try String(contentsOfFile: headPath, encoding: .utf8)
        } catch {
            return (nil, nil)
        }
        let headTrimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if headTrimmed.hasPrefix("ref: refs/heads/") {
            return (String(headTrimmed.dropFirst("ref: refs/heads/".count)), nil)
        }
        guard !headTrimmed.isEmpty else { return (nil, nil) }
        return (nil, headTrimmed)
    }

    /// 연결된 워크트리의 메타데이터(.git 및 HEAD)를 프로세스 실행 없이 파일 I/O로 즉시 해석.
    public static func inspectLinkedWorktree(at path: String, fileManager: FileManager = .default) -> LinkedWorktreeInfo? {
        guard isLinkedWorktree(at: path, fileManager: fileManager) else { return nil }

        let dotGitPath = (path as NSString).appendingPathComponent(".git")
        let content: String
        do {
            content = try String(contentsOfFile: dotGitPath, encoding: .utf8)
        } catch {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }

        let rawGitDir = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGitDir = resolveGitDirPath(raw: rawGitDir, basePath: path)
        let (branch, headCommit) = parseHeadBranchAndCommit(at: resolvedGitDir)

        return LinkedWorktreeInfo(path: path, gitDir: resolvedGitDir, branch: branch, headCommit: headCommit)
    }

    // MARK: - 워크트리 준비 및 고속 생성 파이프라인

    private func reusedWorktreeResult(for request: FastWorktreeRequest, details: String) -> FastWorktreeResult {
        let info = Self.inspectLinkedWorktree(at: request.targetPath)
        return FastWorktreeResult(
            path: request.targetPath,
            branch: info?.branch ?? request.branch,
            reusedExisting: true,
            strategyUsed: request.strategy,
            durationMs: 0.0,
            gitDir: info?.gitDir,
            details: details
        )
    }

    private func ensureTargetParentDirectory(for targetPath: String) {
        let parentDir = (targetPath as NSString).deletingLastPathComponent
        guard !FileManager.default.fileExists(atPath: parentDir) else { return }
        do {
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Worktree parent dir creation error: \(error)\n".utf8))
        }
    }

    /// 워크트리를 준비하거나 생성.
    ///
    /// `request.reuseIfLinked`가 true이고 이미 워크트리가 연결되어 있으면,
    /// Git 명령을 일절 호출하지 않고 0.0ms로 즉시 반환합니다.
    public func prepareWorktree(_ request: FastWorktreeRequest) async throws -> FastWorktreeResult {
        guard !(request.reuseIfLinked && Self.isLinkedWorktree(at: request.targetPath)) else {
            return reusedWorktreeResult(for: request, details: "Reused existing linked worktree (0ms)")
        }

        let lockFile = (request.repoPath as NSString).appendingPathComponent(".worktree-engine.lock")
        return try await lockCoordinator.withLock(lockPath: lockFile, timeout: request.lockTimeout) {
            guard !(request.reuseIfLinked && Self.isLinkedWorktree(at: request.targetPath)) else {
                return self.reusedWorktreeResult(for: request, details: "Reused existing linked worktree (double-checked, 0ms)")
            }

            let startTime = Date()
            self.ensureTargetParentDirectory(for: request.targetPath)
            try await self.executeCreation(request: request)

            if request.autoSetupRemote {
                _ = await self.git(["-C", request.targetPath, "config", "--local", "push.autoSetupRemote", "true"])
            }

            let elapsedMs = Date().timeIntervalSince(startTime) * 1000.0
            return FastWorktreeResult(
                path: request.targetPath,
                branch: request.branch,
                reusedExisting: false,
                strategyUsed: request.strategy,
                durationMs: elapsedMs,
                gitDir: Self.inspectLinkedWorktree(at: request.targetPath)?.gitDir,
                details: "Successfully prepared worktree via \(request.strategy)"
            )
        }
    }

    // MARK: - 전략별 생성 실행기

    private func executeCreation(request: FastWorktreeRequest) async throws {
        switch request.strategy {
        case .standard:
            try await executeStandard(request: request)
        case .noCheckout:
            try await executeNoCheckout(request: request)
        case .sparseCheckout(let paths, let cone):
            try await executeSparseCheckout(request: request, paths: paths, cone: cone)
        case .apfsCoW(let sourceWorktreePath):
            try await executeAPFSCoW(request: request, sourceWorktreePath: sourceWorktreePath)
        }
    }

    /// 표준 워크트리 생성: `git worktree add [-b <branch> | --detach] <path> [<baseRef>]`
    private func executeStandard(request: FastWorktreeRequest) async throws {
        var args = ["worktree", "add"]
        if request.detach {
            args.append("--detach")
        } else if request.createBranch {
            args += ["--no-track", "-b", request.branch]
        }
        args.append(request.targetPath)
        if let baseRef = request.baseRef, !baseRef.isEmpty {
            args.append(baseRef)
        }

        try await runGitWithRetry(repoPath: request.repoPath, args: args, request: request)
    }

    /// 메타데이터 전용 초고속 생성: `git worktree add --no-checkout [-b <branch> | --detach] <path> [<baseRef>]`
    private func executeNoCheckout(request: FastWorktreeRequest) async throws {
        var args = ["worktree", "add", "--no-checkout"]
        if request.detach {
            args.append("--detach")
        } else if request.createBranch {
            args += ["--no-track", "-b", request.branch]
        }
        args.append(request.targetPath)
        if let baseRef = request.baseRef, !baseRef.isEmpty {
            args.append(baseRef)
        }

        try await runGitWithRetry(repoPath: request.repoPath, args: args, request: request)
    }

    /// 워크트리 제거 인프로세스 실행: `git -C <repoPath> worktree remove <targetPath> [--force]`
    @discardableResult
    public func removeWorktree(
        repoPath: String,
        targetPath: String,
        force: Bool = true
    ) async -> CommandResult {
        var args = ["worktree", "remove", targetPath]
        if force {
            args.append("--force")
        }
        return await git(["-C", repoPath] + args)
    }

    /// 희소 체크아웃 기반 분기: `--no-checkout` 생성 후 지정된 경로만 sparse-checkout
    private func executeSparseCheckout(
        request: FastWorktreeRequest,
        paths: [String],
        cone: Bool
    ) async throws {
        // 1. no-checkout으로 워크트리 메타데이터만 즉시 생성
        try await executeNoCheckout(request: request)

        // 2. sparse-checkout 설정
        var sparseArgs = ["-C", request.targetPath, "sparse-checkout", "set"]
        if cone {
            sparseArgs.append("--cone")
        } else {
            sparseArgs.append("--no-cone")
        }
        sparseArgs.append(contentsOf: paths)

        let sparseResult = await git(sparseArgs)
        guard sparseResult.ok else {
            throw FastWorktreeError.gitCommandFailed(
                command: "sparse-checkout set",
                exitCode: sparseResult.exitCode,
                stderr: sparseResult.stderr
            )
        }

        // 3. 선택된 경로만 체크아웃
        let checkoutResult = await git(["-C", request.targetPath, "checkout"])
        guard checkoutResult.ok else {
            throw FastWorktreeError.gitCommandFailed(
                command: "checkout",
                exitCode: checkoutResult.exitCode,
                stderr: checkoutResult.stderr
            )
        }
    }

    /// APFS Copy-on-Write 기반 분기:
    /// 웜 워크트리로부터 `.git`을 제외한 파일들을 CoW 복제하고 인덱스 동기화
    private func executeAPFSCoW(
        request: FastWorktreeRequest,
        sourceWorktreePath: String
    ) async throws {
        // 1. no-checkout으로 대상 워크트리 Git 구조체 생성
        try await executeNoCheckout(request: request)

        // 2. 소스 워크트리에서 .git 제외하고 APFS Copy-on-Write 복제
        do {
            try APFSCoWHelper.cloneDirectoryContents(
                from: sourceWorktreePath,
                to: request.targetPath,
                excluding: [".git"]
            )
        } catch {
            throw FastWorktreeError.apfsCoWFailed(
                source: sourceWorktreePath,
                destination: request.targetPath,
                reason: error.localizedDescription
            )
        }

        // 3. 워크트리 인덱스를 복제된 작업 디렉터리에 맞게 갱신 (reset)
        let resetResult = await git(["-C", request.targetPath, "reset", "--quiet"])
        guard resetResult.ok else {
            throw FastWorktreeError.gitCommandFailed(
                command: "reset",
                exitCode: resetResult.exitCode,
                stderr: resetResult.stderr
            )
        }
    }

    // MARK: - Git 실행 및 락 경합 재시도 헬퍼

    /// 락 경합(index.lock 등) 감지 시 지수 백오프로 재시도하는 Git 실행 래퍼.
    private func runGitWithRetry(
        repoPath: String,
        args: [String],
        request: FastWorktreeRequest
    ) async throws {
        var lastResult: CommandResult?

        for attempt in 0..<request.maxRetries {
            let result = await git(["-C", repoPath] + args)
            if result.ok {
                return
            }

            lastResult = result

            // 락 경합 여부 검사 (index.lock, refs lock 등)
            if WorktreeLockContentionDetector.isLockContention(result.stderr) {
                let delay = WorktreeLockCoordinator.backoffDelay(
                    attempt: attempt,
                    baseDelay: request.retryBaseDelay
                )
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) // lint:allow-sleep
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                continue
            } else {
                // 락 경합이 아닌 다른 Git 오류는 즉시 throw
                throw FastWorktreeError.gitCommandFailed(
                    command: args.joined(separator: " "),
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
            }
        }

        throw FastWorktreeError.exhaustedRetries(
            attempts: request.maxRetries,
            lastError: lastResult?.stderr ?? "알 수 없는 락 경합 실패"
        )
    }

    private func git(_ args: [String]) async -> CommandResult {
        await runner.run(gitPath, args, timeout: 60)
    }
}
