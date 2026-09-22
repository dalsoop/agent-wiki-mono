import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import SingleInstanceKit

@Suite(.serialized)
struct SingleInstanceCrossTenantAndStaleRecoveryTests {
    @Test("크로스 테넌트 락 무충돌: 서로 다른 테넌트는 동일 앱 이름에 대해 독립적으로 락을 점유한다")
    func crossTenantLockNoCollision() throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tenant-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let appName = "ghostty-terminal"
        let tenantA = "tenant-alpha"
        let tenantB = "tenant-beta"
        let tenantC = "tenant-gamma"

        let scopeA = InstanceLockScope.tenant(slug: tenantA, root: rootDir)
        let scopeB = InstanceLockScope.tenant(slug: tenantB, root: rootDir)
        let scopeC = InstanceLockScope.tenant(slug: tenantC, root: rootDir)

        // 1. 3개 테넌트가 동일한 appName으로 동시 락 획득 시도
        let tokenA = SingleInstanceCLI.acquire(name: appName, scope: scopeA)
        let tokenB = SingleInstanceCLI.acquire(name: appName, scope: scopeB)
        let tokenC = SingleInstanceCLI.acquire(name: appName, scope: scopeC)

        #expect(tokenA != nil, "테넌트 A 락 획득 성공해야 함")
        #expect(tokenB != nil, "테넌트 B 락 획득 성공해야 함")
        #expect(tokenC != nil, "테넌트 C 락 획득 성공해야 함")
        #expect(tokenA?.isHeld == true)
        #expect(tokenB?.isHeld == true)
        #expect(tokenC?.isHeld == true)

        // 2. 동일 테넌트 내부에서는 중복 획득 차단 (충돌 방지)
        let tokenA2 = SingleInstanceCLI.acquire(name: appName, scope: scopeA)
        let tokenB2 = SingleInstanceCLI.acquire(name: appName, scope: scopeB)
        #expect(tokenA2 == nil, "테넌트 A 내 동일 앱 중복 실행 차단되어야 함")
        #expect(tokenB2 == nil, "테넌트 B 내 동일 앱 중복 실행 차단되어야 함")

        // 3. UDS 소켓 경로 격리 및 Darwin 104바이트 한계 검증
        let socketA = scopeA.socketURL(name: appName)
        let socketB = scopeB.socketURL(name: appName)
        let socketC = scopeC.socketURL(name: appName)

        #expect(socketA != socketB)
        #expect(socketB != socketC)
        #expect(socketA.path.utf8.count <= InstanceLockScope.maxUDSPathLength)
        #expect(socketB.path.utf8.count <= InstanceLockScope.maxUDSPathLength)
        #expect(socketC.path.utf8.count <= InstanceLockScope.maxUDSPathLength)

        // 4. 해제 검증
        tokenA?.release()
        tokenB?.release()
        tokenC?.release()
    }

    @Test("Stale Lock 파일 복구: 사멸한 프로세스의 PID가 남은 락 파일은 0ms 내에 자가 치유되어 즉시 획득된다")
    func staleLockFileInstantRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "stale-worker-\(UUID().uuidString)"
        let scope = InstanceLockScope.host(directory: tempDir)
        let lockURL = scope.lockFileURL(name: name)

        // 고의로 사멸한 가짜 PID(999999)를 담은 Stale 락 파일 사전 생성
        let stalePID: pid_t = 999999
        try "\(stalePID)\n".write(to: lockURL, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: lockURL.path))

        let coordinator = InstanceLockCoordinator()
        let holderBefore = coordinator.readHolderPID(from: lockURL)
        #expect(holderBefore == stalePID)

        // 커널 flock이 걸려있지 않으므로 새 프로세스가 0ms 내에 즉시 락을 획득하고 자신의 PID로 덮어써야 함
        let startTime = DispatchTime.now()
        let result = coordinator.tryAcquire(name: name, scope: scope)
        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedMillis = Double(elapsedNanos) / 1_000_000.0

        guard case .acquired(let token) = result else {
            Issue.record("Stale 락 파일이 존재하더라도 즉시 획득에 성공해야 함")
            return
        }

        #expect(token.isHeld)
        #expect(elapsedMillis < 50.0, "Stale Lock 복구는 0ms에 가깝게 즉각 수행되어야 함 (실제 소요: \(elapsedMillis)ms)")

        // 락 파일의 PID가 현재 프로세스 PID로 정상 갱신되었는지 검증
        let holderAfter = coordinator.readHolderPID(from: lockURL)
        #expect(holderAfter == getpid())

        token.release()
    }

    @Test("자식 프로세스 강제 종료 후 커널 flock 자동 반환 및 Stale Lock 즉시 회복 검증")
    func childProcessTerminationKernelFlockAutoRelease() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("child-term-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "child-lock-\(UUID().uuidString)"
        let scope = InstanceLockScope.host(directory: tempDir)
        let lockURL = scope.lockFileURL(name: name)

        // 자식 프로세스를 띄워 락을 잡고 대기하도록 함
        // /bin/sh -c 'exec sleep 30'
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "python3 -c 'import fcntl, time, os, sys; f = open(\"\(lockURL.path)\", \"w\"); f.write(str(os.getpid())); f.flush(); fcntl.flock(f, fcntl.LOCK_EX); sys.stdout.write(\"LOCKED\\n\"); sys.stdout.flush(); time.sleep(30)'"]
        process.standardOutput = pipe

        try process.run()
        let childPID = process.processIdentifier

        // 자식이 락을 잡을 때까지 대기
        let reader = pipe.fileHandleForReading
        let lockSignal = String(data: reader.readData(ofLength: 7), encoding: .utf8)
        #expect(lockSignal?.contains("LOCKED") == true)

        let coordinator = InstanceLockCoordinator()
        let busyResult = coordinator.tryAcquire(name: name, scope: scope)
        if case .busy(let holder) = busyResult {
            #expect(holder == childPID || holder != nil)
        } else {
            Issue.record("자식 프로세스가 락을 잡고 있는 동안에는 busy 결과가 나와야 함")
        }

        // 자식 프로세스 SIGKILL 강제 사멸
        process.terminate()
        process.waitUntilExit()

        // 자식이 종료되면 커널이 flock을 즉시 해제하므로 부모가 지연 없이 0ms 즉각 획득 가능해야 함
        let acquireStart = DispatchTime.now()
        let recoveredResult = coordinator.tryAcquire(name: name, scope: scope)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - acquireStart.uptimeNanoseconds) / 1_000_000.0

        guard case .acquired(let token) = recoveredResult else {
            Issue.record("자식 프로세스 종료 후 즉시 Stale Lock이 자가 치유되어 획득되어야 함")
            return
        }

        #expect(token.isHeld)
        #expect(elapsed < 100.0, "소요 시간은 즉각적이어야 함 (실제: \(elapsed)ms)")

        let newHolder = coordinator.readHolderPID(from: lockURL)
        #expect(newHolder == getpid(), "사멸한 자식 PID 대신 현재 프로세스 PID가 기록되어야 함")

        token.release()
    }

    @Test("InstanceProcessGuard.exitIfAlreadyRunning의 Stale Lock 복구 및 정상 토큰 반환")
    func instanceProcessGuardStaleLockRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guard-stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "guard-stale-\(UUID().uuidString)"
        let scope = InstanceLockScope.host(directory: tempDir)
        let lockURL = scope.lockFileURL(name: name)

        // 고의로 사멸된 PID 기록
        try "12345\n".write(to: lockURL, atomically: true, encoding: .utf8)

        var exitCalled = false
        var stderrOutput = ""

        let token = InstanceProcessGuard.exitIfAlreadyRunning(
            name: name,
            scope: scope,
            message: "Should not exit",
            exitCode: 1,
            stderrWriter: { stderrOutput = $0 },
            exitHandler: { _ in exitCalled = true }
        )

        #expect(!exitCalled, "Stale lock 상황에서 프로세스가 종료되면 안 됨")
        #expect(token != nil, "새 토큰이 정상 발급되어야 함")
        #expect(token?.isHeld == true)
        #expect(stderrOutput.isEmpty)

        token?.release()
    }

    @Test("SingleInstanceGuard OOP 평가: Stale Lock 감지 시 staleRecovered 반환 및 자가 치유")
    func oopSingleInstanceGuardStaleRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oop-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let name = "test-oop-app"
        let scope = InstanceLockScope.tenant(slug: "tenant-oop", root: tempDir)
        let lockURL = scope.lockFileURL(name: name)

        // 부모 디렉토리 생성 및 사멸한 PID 파일 미리 작성
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "88888\n".write(to: lockURL, atomically: true, encoding: .utf8)

        let guarder = SingleInstanceGuard()
        let decision = guarder.evaluate(name: name, scope: scope)

        #expect(decision.shouldRun)
        if case .staleRecovered(let prevPID, let token) = decision {
            #expect(prevPID == 88888)
            #expect(token != nil)
            #expect(token?.isHeld == true)
            token?.release()
        } else {
            Issue.record("사멸한 PID가 남은 상태에서는 .staleRecovered 결정이 내려져야 함. 실제: \(decision)")
        }
    }
}
