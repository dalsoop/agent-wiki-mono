import Foundation
import Testing
@testable import SingleInstanceKit

@Suite(.serialized)
struct SingleInstanceCLITests {
    @Test func resolveLockURLFormats() {
        let hostURL = SingleInstanceCLI.resolveLockURL(name: "tool-a", scope: .host)
        #expect(hostURL.path == "/tmp/tool-a.lock")

        let customDir = URL(fileURLWithPath: "/var/tmp")
        let customHostURL = SingleInstanceCLI.resolveLockURL(name: "tool-b.lock", scope: .host(directory: customDir))
        #expect(customHostURL.path == "/var/tmp/tool-b.lock")

        let worktreeDir = URL(fileURLWithPath: "/workspace/my-repo")
        let worktreeURL = SingleInstanceCLI.resolveLockURL(name: "tool-c", scope: .worktree(root: worktreeDir))
        #expect(worktreeURL.path == "/tmp/tool-c-workspace-my-repo.lock")
    }

    @Test func acquireAndRelease() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "test-acquire-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        // 첫 번째 획득 성공
        let token1 = SingleInstanceCLI.acquire(name: name, scope: scope)
        #expect(token1 != nil)
        #expect(token1?.isHeld == true)

        // 같은 프로세스/다른 인스턴스에서 동일 락 획득 시도 시 실패
        let token2 = SingleInstanceCLI.acquire(name: name, scope: scope)
        #expect(token2 == nil)

        // 락 해제
        token1?.release()
        #expect(token1?.isHeld == false)

        // 해제 후 다시 획득 성공
        let token3 = SingleInstanceCLI.acquire(name: name, scope: scope)
        #expect(token3 != nil)
        #expect(token3?.isHeld == true)
        token3?.release()
    }

    @Test func worktreeScopeIsolation() throws {
        let dirA = FileManager.default.temporaryDirectory.appendingPathComponent("wtA-\(UUID().uuidString)")
        let dirB = FileManager.default.temporaryDirectory.appendingPathComponent("wtB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }

        let name = "lint-tool"
        let scopeA: SingleInstanceCLI.Scope = .worktree(root: dirA)
        let scopeB: SingleInstanceCLI.Scope = .worktree(root: dirB)

        // 서로 다른 워크트리에서는 같은 name이어도 각각 락 획득 가능
        let tokenA = SingleInstanceCLI.acquire(name: name, scope: scopeA)
        let tokenB = SingleInstanceCLI.acquire(name: name, scope: scopeB)

        #expect(tokenA != nil)
        #expect(tokenB != nil)

        // dirA 내부에서 중복 획득 시도는 실패
        let tokenA2 = SingleInstanceCLI.acquire(name: name, scope: scopeA)
        #expect(tokenA2 == nil)

        tokenA?.release()
        tokenB?.release()
    }

    @Test func exitIfAlreadyRunningBehavior() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "exit-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        var exitedCode: Int32?
        var stderrMessages: [String] = []

        // 1. 점유되지 않은 상태: exitHandler 미호출, 토큰 반환
        let initialToken = SingleInstanceCLI.exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: "Custom busy message",
            exitCode: 42,
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { exitedCode = $0 }
        )
        #expect(initialToken != nil)
        #expect(exitedCode == nil)
        #expect(stderrMessages.isEmpty)

        // 2. 이미 점유된 상태: exitHandler 호출 및 stderr 메시지 출력
        let duplicateToken = SingleInstanceCLI.exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: "Custom busy message",
            exitCode: 42,
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { exitedCode = $0 }
        )
        #expect(duplicateToken == nil)
        #expect(exitedCode == 42)
        #expect(stderrMessages.contains("Custom busy message"))

        initialToken?.release()
    }

    @Test func findWorktreeRootResolvesFromSubdir() {
        let currentPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = SingleInstanceCLI.findWorktreeRoot(from: currentPath)
        // 현재 레포(.worktrees/main)의 루트에는 .git이 존재해야 함
        let gitPath = root.appendingPathComponent(".git").path
        #expect(FileManager.default.fileExists(atPath: gitPath))
    }

    @Test func acquireRecordsCurrentPIDInLockFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "pid-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        guard let token = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire initial token")
            return
        }
        #expect(!token.isBypassed)

        // 락 파일에 현재 프로세스 PID가 기록되어 있는지 확인
        let recordedPID = SingleInstanceCLI.readHolderPID(from: token.lockURL)
        #expect(recordedPID == getpid())

        // 락 해제 후 내용이 비워졌는지 확인
        token.release()
        let postReleasePID = SingleInstanceCLI.readHolderPID(from: token.lockURL)
        #expect(postReleasePID == nil)
    }

    @Test func inheritanceBypassWithAllowRecursionEnvironment() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "recursion-env-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        // 부모 프로세스가 락을 잡음
        guard let parentToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire parent token")
            return
        }
        #expect(parentToken.isHeld)
        #expect(!parentToken.isBypassed)

        // 플래그 없이 재획득 시도 시 차단
        let blockedToken = SingleInstanceCLI.acquire(name: name, scope: scope, environment: [:], arguments: [])
        #expect(blockedToken == nil)

        // SINGLE_INSTANCE_ALLOW_RECURSION=1 환경변수 부여 시 자가 교착 방지 bypass 허용
        let childToken = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: ["SINGLE_INSTANCE_ALLOW_RECURSION": "1"],
            arguments: []
        )
        #expect(childToken != nil)
        #expect(childToken?.isBypassed == true)
        #expect(childToken?.isHeld == true)

        // 자식 토큰 해제 시 부모 토큰은 여전히 유지되어야 함
        childToken?.release()
        #expect(childToken?.isHeld == false)
        #expect(parentToken.isHeld)

        parentToken.release()
        #expect(!parentToken.isHeld)
    }

    @Test func inheritanceBypassWithParentPIDEnvironment() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "parent-pid-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        guard let parentToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire parent token")
            return
        }

        let simulatedParentPID: pid_t = 12345

        // SINGLE_INSTANCE_PARENT_PID가 현재 currentPPID와 일치할 때 bypass 허용
        let matchingChildToken = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: ["SINGLE_INSTANCE_PARENT_PID": "\(simulatedParentPID)"],
            arguments: [],
            currentPPID: simulatedParentPID
        )
        #expect(matchingChildToken != nil)
        #expect(matchingChildToken?.isBypassed == true)
        matchingChildToken?.release()

        // SINGLE_INSTANCE_PARENT_PID가 currentPPID와 불일치할 때 bypass 거부
        let mismatchChildToken = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: ["SINGLE_INSTANCE_PARENT_PID": "99999"],
            arguments: [],
            currentPPID: 88888
        )
        #expect(mismatchChildToken == nil)

        parentToken.release()
    }

    @Test func inheritanceBypassWithCommandLineArguments() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "args-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        guard let parentToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire parent token")
            return
        }

        // --allow-concurrent 인자 테스트
        let concurrentToken = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: [:],
            arguments: ["my-cli", "--allow-concurrent"]
        )
        #expect(concurrentToken != nil)
        #expect(concurrentToken?.isBypassed == true)
        concurrentToken?.release()

        // --force 인자 테스트
        let forceToken = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: [:],
            arguments: ["my-cli", "--force"]
        )
        #expect(forceToken != nil)
        #expect(forceToken?.isBypassed == true)
        forceToken?.release()

        parentToken.release()
    }

    @Test func inheritanceBypassWithConcurrentEnvironment() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "concurrent-env-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        guard let parentToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire parent token")
            return
        }

        // SINGLE_INSTANCE_ALLOW_CONCURRENT=1
        let token1 = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: ["SINGLE_INSTANCE_ALLOW_CONCURRENT": "1"],
            arguments: []
        )
        #expect(token1 != nil)
        #expect(token1?.isBypassed == true)
        token1?.release()

        // SINGLE_INSTANCE_FORCE=1
        let token2 = SingleInstanceCLI.acquire(
            name: name,
            scope: scope,
            environment: ["SINGLE_INSTANCE_FORCE": "1"],
            arguments: []
        )
        #expect(token2 != nil)
        #expect(token2?.isBypassed == true)
        token2?.release()

        parentToken.release()
    }

    @Test func exitIfAlreadyRunningWithRecursionBypass() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "exit-bypass-test-\(UUID().uuidString)"
        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        // 부모 락 점유
        guard let parentToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            Issue.record("Failed to acquire parent token")
            return
        }

        var exitedCode: Int32?
        var stderrMessages: [String] = []

        // 재귀 허용 환경변수가 있을 때 exitHandler 호출 없이 bypass 토큰 반환 확인
        let bypassToken = SingleInstanceCLI.exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: "Should not be printed",
            exitCode: 99,
            environment: ["SINGLE_INSTANCE_ALLOW_RECURSION": "1"],
            arguments: [],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { exitedCode = $0 }
        )

        #expect(bypassToken != nil)
        #expect(bypassToken?.isBypassed == true)
        #expect(exitedCode == nil)
        #expect(stderrMessages.isEmpty)

        bypassToken?.release()
        parentToken.release()
    }

    @Test func makeRecursionEnvironmentHelper() {
        let baseEnv = ["EXISTING_KEY": "EXISTING_VAL"]
        let recursionEnv = SingleInstanceCLI.makeRecursionEnvironment(base: baseEnv)

        #expect(recursionEnv["EXISTING_KEY"] == "EXISTING_VAL")
        #expect(recursionEnv["SINGLE_INSTANCE_ALLOW_RECURSION"] == "1")
        #expect(recursionEnv["SINGLE_INSTANCE_PARENT_PID"] == "\(getpid())")
    }

    @Test func tenantScopeIsolation() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("tenant-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let name = "fleet-app"
        let gujoScope: SingleInstanceCLI.Scope = .tenant(slug: "gujo", root: rootDir)
        let silneobalScope: SingleInstanceCLI.Scope = .tenant(slug: "silneobal", root: rootDir)

        // 동일 디렉토리 내에서도 서로 다른 테넌트는 독립적으로 락을 획득할 수 있어야 함
        let gujoToken = SingleInstanceCLI.acquire(name: name, scope: gujoScope)
        let silneobalToken = SingleInstanceCLI.acquire(name: name, scope: silneobalScope)

        #expect(gujoToken != nil)
        #expect(silneobalToken != nil)

        // 같은 테넌트 내에서는 중복 획득 차단
        let gujoToken2 = SingleInstanceCLI.acquire(name: name, scope: gujoScope)
        #expect(gujoToken2 == nil)

        gujoToken?.release()
        silneobalToken?.release()
    }

    @Test func udsSocketPathDarwinLimitSafety() {
        let deepWorktree = URL(fileURLWithPath: "/Users/jeonghan/Documents/WORK/WORKSPACE")
            .appendingPathComponent("apps/swift-app-mono/.worktrees")
            .appendingPathComponent("feature-branch-with-very-very-long-name-exceeding-standard-unix-domain-socket-limit")
        let scope = InstanceLockScope.tenant(slug: "tenant-enterprise-department-subdivision", root: deepWorktree)
        let socketURL = scope.socketURL(name: "super-long-application-bundle-identifier-name")

        #expect(socketURL.path.hasPrefix("/tmp/sik_"))
        #expect(socketURL.path.hasSuffix(".sock"))
        #expect(socketURL.path.utf8.count <= InstanceLockScope.maxUDSPathLength)
    }

    @Test func instanceLockCoordinatorDirectUsage() throws {
        let coordinator = InstanceLockCoordinator()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scope = InstanceLockScope.host(directory: tempDir)
        let name = "coord-test-\(UUID().uuidString)"

        let res1 = coordinator.tryAcquire(name: name, scope: scope)
        guard case .acquired(let token1) = res1 else {
            Issue.record("Expected acquired token")
            return
        }
        #expect(token1.isHeld)

        let res2 = coordinator.tryAcquire(name: name, scope: scope)
        guard case .busy = res2 else {
            Issue.record("Expected busy result")
            return
        }

        token1.release()
        #expect(!token1.isHeld)

        let res3 = coordinator.tryAcquire(name: name, scope: scope)
        guard case .acquired(let token3) = res3 else {
            Issue.record("Expected acquired token after release")
            return
        }
        token3.release()
    }

    @Test func guardStandardInformationalBypass() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "guard-test-\(UUID().uuidString)"
        let scope = SingleInstanceCLI.Scope.host(directory: tempDir)

        // 1. help 커맨드는 락을 잡지 않고 바이패스 (nil 반환)
        let tokenHelp = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: ["my-tool", "help"]
        )
        #expect(tokenHelp == nil)

        // 2. capabilities 커맨드 바이패스
        let tokenCaps = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: ["my-tool", "capabilities", "--json"]
        )
        #expect(tokenCaps == nil)

        // 3. --version 플래그 바이패스
        let tokenVer = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: ["my-tool", "--version"]
        )
        #expect(tokenVer == nil)

        // 4. 일반 커맨드는 락 정상 획득
        let tokenRun = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: ["my-tool", "dispatch", "--job", "123"]
        )
        #expect(tokenRun != nil)
        #expect(tokenRun?.isHeld == true)

        // 5. 락이 점유된 상태에서 --force 플래그는 바이패스
        let tokenForce = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: ["my-tool", "dispatch", "--force"]
        )
        #expect(tokenForce == nil)

        tokenRun?.release()
    }

    @Test func autoGuardExtractsBinaryNameAndBypasses() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scope: SingleInstanceCLI.Scope = .host(directory: tempDir)

        // 1. autoGuard 로 help 바이패스 (바이너리 경로에서 이름 자동 추출)
        let tokenHelp = SingleInstanceCLI.autoGuard(
            scope: scope,
            arguments: ["/usr/local/bin/agent-test-tool", "help"]
        )
        #expect(tokenHelp == nil)

        // 2. autoGuard 로 open 바이패스
        let tokenOpen = SingleInstanceCLI.autoGuard(
            scope: scope,
            arguments: ["/usr/local/bin/agent-test-tool", "open"]
        )
        #expect(tokenOpen == nil)

        // 3. autoGuard 일반 실행 락 획득
        let tokenExec = SingleInstanceCLI.autoGuard(
            scope: scope,
            arguments: ["/usr/local/bin/agent-test-tool", "process", "--all"]
        )
        #expect(tokenExec != nil)
        #expect(tokenExec?.isHeld == true)

        tokenExec?.release()
    }
}
