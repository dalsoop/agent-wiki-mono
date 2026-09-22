import Foundation
import Testing
@testable import LicenseCacheKit

@Suite("EntitlementEvaluator Fallback Order Tests")
struct EntitlementEvaluatorTests {

    @Test("1단계: 서버 정상 응답 시 available 반환 및 캐시 갱신")
    func testServerAvailableWinsAndCaches() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = OfflineLicenseStore(directory: tempDir.appendingPathComponent("licenses"))
        let cache = EntitlementCache(cacheFileURL: tempDir.appendingPathComponent("cache/entitlements.json"))
        let evaluator = EntitlementEvaluator(store: store, cache: cache)

        let status = await evaluator.evaluate(bundleId: "kr.gujo.test-app") {
            return .available
        }

        #expect(status == .available)
        // 캐시에도 저장되었는지 확인
        #expect(cache.get(bundleId: "kr.gujo.test-app") == .available)
    }

    @Test("2단계: 서버 불능 시 캐시에서 available 반환")
    func testServerFailureFallsBackToCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = OfflineLicenseStore(directory: tempDir.appendingPathComponent("licenses"))
        let cache = EntitlementCache(cacheFileURL: tempDir.appendingPathComponent("cache/entitlements.json"))
        // 사전에 캐시 저장
        cache.set(bundleId: "kr.gujo.cached-app", status: .available)

        let evaluator = EntitlementEvaluator(store: store, cache: cache)

        struct NetworkError: Error {}
        let status = await evaluator.evaluate(bundleId: "kr.gujo.cached-app") {
            throw NetworkError() // 서버 통신 실패 (오프라인)
        }

        #expect(status == .available)
    }

    @Test("3단계: 서버 불능 및 캐시 만료/부재 시 오프라인 라이선스 파일로 available 반환")
    func testServerAndCacheFailureFallsBackToOfflineFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (privateKey, publicKey) = OfflineLicenseValidator.generateKeyPair()
        let validator = OfflineLicenseValidator(publicKey: publicKey)
        let store = OfflineLicenseStore(directory: tempDir.appendingPathComponent("licenses"), validator: validator)
        let cache = EntitlementCache(cacheFileURL: tempDir.appendingPathComponent("cache/entitlements.json"))

        // 오프라인 라이선스 파일 활성화
        let issued = try OfflineLicenseValidator.sign(
            bundleId: "kr.gujo.offline-app",
            plan: "pro",
            privateKey: privateKey
        )
        try store.activate(jsonString: issued.json)

        let evaluator = EntitlementEvaluator(store: store, cache: cache)

        struct ServerDownError: Error {}
        let status = await evaluator.evaluate(bundleId: "kr.gujo.offline-app") {
            throw ServerDownError() // 서버 불능
        }

        #expect(status == .available)
    }

    @Test("4단계: 서버 불능, 캐시 부재, 오프라인 파일 부재 시 notConnected 반환")
    func testAllFallbackFailsReturnsNotConnected() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = OfflineLicenseStore(directory: tempDir.appendingPathComponent("licenses"))
        let cache = EntitlementCache(cacheFileURL: tempDir.appendingPathComponent("cache/entitlements.json"))
        let evaluator = EntitlementEvaluator(store: store, cache: cache)

        struct ServerDownError: Error {}
        let status = await evaluator.evaluate(bundleId: "kr.gujo.unknown-app") {
            throw ServerDownError()
        }

        #expect(status == .notConnected)
    }

    @Test("서버가 명시적으로 notEntitled 반환 시 notEntitled 반환")
    func testServerNotEntitledReturnsNotEntitled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = OfflineLicenseStore(directory: tempDir.appendingPathComponent("licenses"))
        let cache = EntitlementCache(cacheFileURL: tempDir.appendingPathComponent("cache/entitlements.json"))
        let evaluator = EntitlementEvaluator(store: store, cache: cache)

        let status = await evaluator.evaluate(bundleId: "kr.gujo.not-owned-app") {
            return .notEntitled
        }

        #expect(status == .notEntitled)
    }
}
