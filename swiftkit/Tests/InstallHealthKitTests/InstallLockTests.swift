import Foundation
import Testing
@testable import InstallHealthKit

@Suite("InstallLock 동시성 락 검증")
struct InstallLockTests {

    @Test("단일 프로세스 락 획득 및 해제 검증")
    func singleProcessAcquireAndRelease() throws {
        let slug = "test-lock-\(UUID().uuidString)"
        #expect(!InstallLock.isLocked(slug: slug))

        let token = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
        #expect(token != nil)
        #expect(InstallLock.isLocked(slug: slug))

        token?.unlock()
        #expect(!InstallLock.isLocked(slug: slug))

        // clean up lock file if exists
        try? FileManager.default.removeItem(atPath: InstallLock.lockPath(slug: slug))
    }

    @Test("논블로킹 경합 시 두 번째 락 획득 실패 검증")
    func nonBlockingContentionFails() throws {
        let slug = "test-contention-\(UUID().uuidString)"

        guard let token1 = try InstallLock.acquire(slug: slug, timeoutSeconds: 0) else {
            Issue.record("첫 번째 락 획득 실패")
            return
        }
        defer {
            token1.unlock()
            try? FileManager.default.removeItem(atPath: InstallLock.lockPath(slug: slug))
        }

        // 두 번째 락 획득 시도: 논블로킹(timeout 0)이므로 실패(nil)해야 함
        let token2 = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
        #expect(token2 == nil)

        // 첫 번째 락 해제 후에는 다시 획득 가능해야 함
        token1.unlock()
        #expect(!InstallLock.isLocked(slug: slug))

        let token3 = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
        #expect(token3 != nil)
        token3?.unlock()
    }

    @Test("withLock 스코프 내 배타 락 유지 및 종료 후 자동 해제")
    func withLockScopeExclusion() throws {
        let slug = "test-withlock-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: InstallLock.lockPath(slug: slug))
        }

        var executed = false
        try InstallLock.withLock(slug: slug, timeoutSeconds: 5) {
            executed = true
            #expect(InstallLock.isLocked(slug: slug))
            // 스코프 내에서 다른 락 획득 시도 시 실패
            let secondToken = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
            #expect(secondToken == nil)
        }

        #expect(executed)
        #expect(!InstallLock.isLocked(slug: slug))
    }

    @Test("async withLock 비동기 스코프 락 보호 검증")
    func asyncWithLockScopeExclusion() async throws {
        let slug = "test-async-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: InstallLock.lockPath(slug: slug))
        }

        var executed = false
        try await InstallLock.withLock(slug: slug, timeoutSeconds: 5) {
            executed = true
            #expect(InstallLock.isLocked(slug: slug))
            let second = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
            #expect(second == nil)
        }

        #expect(executed)
        #expect(!InstallLock.isLocked(slug: slug))
    }

    @Test("RAII 토큰 deinit 시 자동 락 해제 검증")
    func tokenRAIIDeinitUnlocks() throws {
        let slug = "test-raii-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(atPath: InstallLock.lockPath(slug: slug))
        }

        do {
            let token = try InstallLock.acquire(slug: slug, timeoutSeconds: 0)
            #expect(token != nil)
            #expect(InstallLock.isLocked(slug: slug))
            _ = token // deallocated at end of scope
        }

        #expect(!InstallLock.isLocked(slug: slug))
    }
}
