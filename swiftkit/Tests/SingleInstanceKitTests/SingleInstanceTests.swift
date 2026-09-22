import Testing
import os
#if canImport(AppKit)
import AppKit
#endif
@testable import SingleInstanceKit

private struct StubQuery: RunningInstanceQuerying {
    let count: Int
    func otherInstanceCount(bundleIdentifier: String) -> Int { count }
}

@Suite(.serialized)
struct SingleInstanceTests {
    @Test func exitsWhenAnotherInstanceExists() {
        #expect(SingleInstance.shouldExit(query: StubQuery(count: 1), bundleIdentifier: "a.b"))
    }

    @Test func staysWhenAlone() {
        #expect(!SingleInstance.shouldExit(query: StubQuery(count: 0), bundleIdentifier: "a.b"))
    }

    @Test func staysWithoutBundleID() {
        #expect(!SingleInstance.shouldExit(query: StubQuery(count: 3), bundleIdentifier: nil))
        #expect(!SingleInstance.shouldExit(query: StubQuery(count: 3), bundleIdentifier: ""))
    }

    @Test func productLockBlocksProductionDevelopmentAndRawLaunchesWithOneCanonicalKey() throws {
        let directory = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let canonicalKey = "net.ranode.fleet-dock-\(UUID().uuidString)"
        var exitCodes: [Int32] = []
        var messages: [String] = []

        let production = SingleInstance.acquireOrExit(
            lockName: canonicalKey,
            lockDirectory: directory,
            stderrWriter: { messages.append($0) },
            exitHandler: { exitCodes.append($0) }
        )
        let developmentOrRaw = SingleInstance.acquireOrExit(
            lockName: canonicalKey,
            lockDirectory: directory,
            stderrWriter: { messages.append($0) },
            exitHandler: { exitCodes.append($0) }
        )

        #expect(production?.isHeld == true)
        #expect(developmentOrRaw == nil)
        #expect(exitCodes == [0])
        #expect(messages.count == 1)
        #expect(messages[0].contains(canonicalKey))
        production?.release()
    }

    @Test func productLockAllowsRelaunchAfterTheOwnerExits() throws {
        let directory = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let canonicalKey = "net.ranode.fleet-dock-\(UUID().uuidString)"
        let first = SingleInstance.acquireOrExit(
            lockName: canonicalKey,
            lockDirectory: directory,
            stderrWriter: { _ in },
            exitHandler: { _ in }
        )
        #expect(first?.isHeld == true)
        first?.release()

        let relaunched = SingleInstance.acquireOrExit(
            lockName: canonicalKey,
            lockDirectory: directory,
            stderrWriter: { _ in },
            exitHandler: { _ in }
        )
        #expect(relaunched?.isHeld == true)
        relaunched?.release()
    }

    @Test func simultaneousLaunchRaceProducesExactlyOneOwner() async throws {
        let directory = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let canonicalKey = "net.ranode.fleet-dock-race-\(UUID().uuidString)"
        let owners = await withTaskGroup(
            of: SingleInstanceCLI.Token?.self,
            returning: [SingleInstanceCLI.Token].self
        ) { group in
            for _ in 0..<16 {
                group.addTask {
                    SingleInstance.acquireOrExit(
                        lockName: canonicalKey,
                        lockDirectory: directory,
                        stderrWriter: { _ in },
                        exitHandler: { _ in }
                    )
                }
            }

            var acquired: [SingleInstanceCLI.Token] = []
            for await token in group {
                if let token { acquired.append(token) }
            }
            return acquired
        }

        #expect(owners.count == 1)
        owners.forEach { $0.release() }
    }

    @Test func productLockDoesNotBlockAnotherProduct() throws {
        let directory = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let suffix = UUID().uuidString
        let fleetDock = SingleInstance.acquireOrExit(
            lockName: "net.ranode.fleet-dock-\(suffix)",
            lockDirectory: directory,
            stderrWriter: { _ in },
            exitHandler: { _ in }
        )
        let anotherProduct = SingleInstance.acquireOrExit(
            lockName: "net.ranode.another-product-\(suffix)",
            lockDirectory: directory,
            stderrWriter: { _ in },
            exitHandler: { _ in }
        )

        #expect(fleetDock?.isHeld == true)
        #expect(anotherProduct?.isHeld == true)
        fleetDock?.release()
        anotherProduct?.release()
    }

    @Test func visibleWindowSuppressesDefaultReopen() {
        let decision = WindowReopenPolicy.decide(
            hasVisibleWindows: true,
            windows: [.init(isVisible: true, isKey: true, isMain: true, isNormal: true)]
        )

        #expect(decision == .activateExisting)
    }

    @Test func hiddenNormalWindowRestoresExactlyOne() {
        let decision = WindowReopenPolicy.decide(
            hasVisibleWindows: false,
            windows: [
                .init(isVisible: false, isKey: false, isMain: false, isNormal: true),
                .init(isVisible: false, isKey: false, isMain: true, isNormal: true),
                .init(isVisible: false, isKey: false, isMain: false, isNormal: true),
            ]
        )

        #expect(decision == .restore(index: 1))
    }

    @Test func noRestorableWindowAllowsDefaultReopen() {
        let decision = WindowReopenPolicy.decide(hasVisibleWindows: false, windows: [])

        #expect(decision == .allowDefault)
    }

    @Test func hiddenPanelDoesNotReplaceMainWindow() {
        let decision = WindowReopenPolicy.decide(
            hasVisibleWindows: false,
            windows: [.init(isVisible: false, isKey: false, isMain: false, isNormal: false)]
        )

        #expect(decision == .allowDefault)
    }

    #if canImport(AppKit)
    @MainActor
    @Test func windowReopenDelegateTerminatesAfterLastWindowClosedByDefault() {
        let delegate = WindowReopenDelegate()
        #expect(delegate.terminatesAfterLastWindowClosed)
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
    #endif

    // MARK: - MurmurHash64A & Fixed Length UDS Socket Path Tests

    @Test func murmurHash30ByteFixedLengthSocketPath() {
        let keys = [
            "",
            "a",
            "fleet-dock",
            "net.ranode.fleet-dock.main.window",
            "a".repeating(200),
            "tenant:enterprise-division-dept-99:worktree:/very/long/deep/nested/path/to/project:app-daemon"
        ]

        for key in keys {
            let path = SingleInstance.socketPath(for: key)
            let url = SingleInstance.socketURL(for: key)

            // 정확히 30바이트 고정 길이 검증
            #expect(path.utf8.count == 30, "Socket path '\(path)' must be exactly 30 bytes")
            #expect(path.hasPrefix("/tmp/sik_"))
            #expect(path.hasSuffix(".sock"))
            #expect(url.path == path)

            // 16자리 hex 해시 확인
            let hexPart = String(path.dropFirst("/tmp/sik_".count).dropLast(".sock".count))
            #expect(hexPart.count == 16)
            #expect(UInt64(hexPart, radix: 16) != nil)

            // 결정론적 일관성 검증
            #expect(SingleInstance.socketPath(for: key) == path)
        }
    }

    // MARK: - Tenant Isolation Lock File Path Tests

    @Test func tenantIsolationLockFilePath() throws {
        let defaultURL = SingleInstance.tenantLockURL(slug: "team-alpha", name: "daemon")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expectedDefault = home.appendingPathComponent(".tenants/team-alpha/.locks/daemon.lock")
        #expect(defaultURL.path == expectedDefault.path)

        let customRoot = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: customRoot) }

        let customTenantURL = SingleInstance.tenantLockURL(slug: "team-beta", name: "worker.lock", root: customRoot)
        let expectedCustom = customRoot.appendingPathComponent(".tenants/team-beta/.locks/worker.lock")
        #expect(customTenantURL.path == expectedCustom.path)

        // 서로 다른 테넌트 간 충돌 방지 검증
        let tenantA = SingleInstance.tenantLockURL(slug: "tenant-a", name: "tool", root: customRoot)
        let tenantB = SingleInstance.tenantLockURL(slug: "tenant-b", name: "tool", root: customRoot)
        #expect(tenantA.path != tenantB.path)
    }

    // MARK: - ProcessProbing Tests

    @Test func systemProcessProberLiveness() {
        let prober = SystemProcessProber()

        // 현재 실행 중인 프로세스 검사 -> true
        #expect(prober.isProcessAlive(pid: getpid()))

        // 미존재 PID (사망한 프로세스) -> false (ESRCH)
        let nonExistentPID: pid_t = 999_999_99
        #expect(!prober.isProcessAlive(pid: nonExistentPID))
        #expect(!prober.isProcessAlive(pid: -1))
    }

    // MARK: - Stale Lock Self-Healing Tests

    @Test func staleLockSelfHealingWithDeadPID() throws {
        let dir = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let lockURL = dir.appendingPathComponent("stale-test.lock")
        let deadPID: pid_t = 999_999_99

        // 의도적으로 사망한 프로세스의 PID가 적힌 Stale Lock 파일 생성
        try "\(deadPID)\n".write(to: lockURL, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: lockURL.path))

        let scope = InstanceLockScope.host(directory: dir)
        let decision = SingleInstance.evaluate(name: "stale-test", scope: scope)

        // ESRCH 감지 후 자가 치유되어 staleRecovered 결정 반환 확인
        guard case .staleRecovered(let prevPID, let token) = decision else {
            Issue.record("Expected .staleRecovered but got \(decision)")
            return
        }

        #expect(prevPID == deadPID)
        #expect(decision.shouldRun)
        #expect(token != nil)
        #expect(token?.isHeld == true)

        // 파일에 현재 프로세스 PID가 올바르게 덮어씌워졌는지 확인
        let content = try String(contentsOf: lockURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(content == "\(getpid())")

        token?.release()
    }

    @Test func guardDecisionYieldToExistingWhenHolderAlive() throws {
        let dir = try temporaryLockDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let name = "active-holder-test"
        let scope = InstanceLockScope.host(directory: dir)

        // 1. 첫 번째 프로세스가 정상 락 획득
        let firstDecision = SingleInstance.evaluate(name: name, scope: scope)
        guard case .run(let token) = firstDecision else {
            Issue.record("Expected .run for first instance")
            return
        }
        #expect(firstDecision.shouldRun)
        #expect(token?.isHeld == true)

        // 2. 살아있는 홀더가 있는 상태에서 두 번째 인스턴스 시도
        let secondDecision = SingleInstance.evaluate(name: name, scope: scope)
        guard case .yieldToExisting(let holderPID) = secondDecision else {
            Issue.record("Expected .yieldToExisting for second instance")
            return
        }
        #expect(!secondDecision.shouldRun)
        #expect(holderPID == getpid())

        token?.release()
    }

    // MARK: - Protocol DI Unit Tests (Mocks)

    @Test func instanceGuardingProtocolDIWithMocks() {
        let mockLock = MockInstanceLocking()
        let mockProber = MockProcessProber(alivePIDs: [2001])
        let guarder = SingleInstanceGuard(locking: mockLock, prober: mockProber)
        let scope = InstanceLockScope.host(directory: URL(fileURLWithPath: "/mock"))

        // Case 1: 콜드 스타트 락 획득 성공 -> .run
        mockLock.canAcquire = true
        let dec1 = guarder.evaluate(name: "service", scope: scope)
        #expect(dec1.shouldRun)
        if case .run = dec1 {} else { Issue.record("Expected .run") }

        // Case 2: 락 획득 실패 & 홀더 PID 2001 생존 -> .yieldToExisting
        mockLock.canAcquire = false
        mockLock.storedPID = 2001
        let dec2 = guarder.evaluate(name: "service", scope: scope)
        #expect(!dec2.shouldRun)
        #expect(dec2.holderPID == 2001)
        if case .yieldToExisting(let pid) = dec2 {
            #expect(pid == 2001)
        } else {
            Issue.record("Expected .yieldToExisting")
        }

        // Case 3: 락 획득 실패 & 홀더 PID 3001 사망(ESRCH) -> 언링크 후 재획득 성공 -> .staleRecovered
        mockLock.canAcquire = true // 언링크 후 재시도 시 획득 가능
        mockLock.storedPID = 3001 // prober에 없는 사망 PID
        let dec3 = guarder.evaluate(name: "service", scope: scope)
        #expect(dec3.shouldRun)
        if case .staleRecovered(let prevPID, _) = dec3 {
            #expect(prevPID == 3001)
        } else {
            Issue.record("Expected .staleRecovered")
        }
        #expect(mockLock.removedURLs.count == 1)
    }

    @Test func exitIfAlreadyRunningNonTerminatingExitHandler() {
        let mockLock = MockInstanceLocking()
        mockLock.canAcquire = false
        mockLock.storedPID = 5555
        let mockProber = MockProcessProber(alivePIDs: [5555])
        let guarder = SingleInstanceGuard(locking: mockLock, prober: mockProber)

        var exitCalledWith: Int32?
        var stderrMessages: [String] = []

        let decision = SingleInstance.exitIfAlreadyRunning(
            name: "test-non-terminate",
            scope: .host,
            guarder: guarder,
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { exitCalledWith = $0 }
        )

        #expect(decision == .yieldToExisting(holderPID: 5555))
        #expect(exitCalledWith == 0)
        #expect(stderrMessages.count == 1)
        #expect(stderrMessages[0].contains("PID 5555"))
    }

    private func temporaryLockDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-instance-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

// MARK: - Test Mocks

private struct MockProcessProber: ProcessProbing {
    let alivePIDs: Set<pid_t>
    func isProcessAlive(pid: pid_t) -> Bool {
        alivePIDs.contains(pid)
    }
}

private final class MockInstanceLocking: InstanceLocking, Sendable {
    private struct State {
        var storedPID: pid_t?
        var canAcquire = true
        var acquiredURLs: [URL] = []
        var removedURLs: [URL] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var storedPID: pid_t? {
        get { state.withLock { $0.storedPID } }
        set { state.withLock { $0.storedPID = newValue } }
    }

    var canAcquire: Bool {
        get { state.withLock { $0.canAcquire } }
        set { state.withLock { $0.canAcquire = newValue } }
    }

    var acquiredURLs: [URL] { state.withLock { $0.acquiredURLs } }
    var removedURLs: [URL] { state.withLock { $0.removedURLs } }

    func tryAcquire(url: URL) -> InstanceLockToken? {
        let acquired = state.withLock { state -> Bool in
            guard state.canAcquire else { return false }
            state.acquiredURLs.append(url)
            state.storedPID = getpid()
            return true
        }
        return acquired ? InstanceLockToken(bypassedURL: url, reason: "mock-acquire") : nil
    }

    func readHolderPID(from url: URL) -> pid_t? {
        state.withLock { $0.storedPID }
    }

    func writeHolderPID(_ pid: pid_t, to url: URL) {
        state.withLock { $0.storedPID = pid }
    }

    func removeLockFile(at url: URL) -> Bool {
        state.withLock {
            $0.removedURLs.append(url)
            $0.storedPID = nil
        }
        return true
    }
}

private extension String {
    func repeating(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
