import XCTest
@testable import AgentTierKit

final class TierPolicyTests: XCTestCase {
    private func tempPolicyURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agenttierkit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("policy.json", isDirectory: false)
    }

    func testDefaultPolicyLoadCreatesFile() {
        let url = tempPolicyURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let store = TierPolicyStore(url: url)
        let policy = store.load()

        XCTAssertEqual(policy.provider, "kiro")
        XCTAssertEqual(policy.configs.count, AgentTier.allCases.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testModelLookupPerTier() {
        let policy = TierPolicy.defaultPolicy
        // 기본 정책의 모든 티어 모델은 nil(defer) — 워커가 각자 계정 기본 모델을 쓴다.
        XCTAssertNil(policy.model(for: .meta))
        XCTAssertNil(policy.model(for: .coordinator))
        XCTAssertNil(policy.model(for: .worker))
        XCTAssertNil(policy.model(for: .verifier))

        XCTAssertEqual(policy.config(for: .worker)?.effort, "medium")
        XCTAssertEqual(policy.config(for: .worker)?.maxConcurrent, 4)
    }

    func testSaveAndReloadRoundTrip() throws {
        let url = tempPolicyURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TierPolicyStore(url: url)

        var policy = store.load()
        let updatedWorker = TierConfig(
            tier: .worker,
            model: "custom-model",
            effort: "high",
            maxConcurrent: 8,
            fallbackModel: "custom-fallback"
        )
        policy = TierPolicy(
            configs: policy.configs.map { $0.tier == .worker ? updatedWorker : $0 },
            provider: policy.provider
        )
        try store.save(policy)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.model(for: .worker), "custom-model")
        XCTAssertEqual(reloaded.config(for: .worker)?.maxConcurrent, 8)
    }

    func testResetToDefaults() throws {
        let url = tempPolicyURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = TierPolicyStore(url: url)

        var policy = store.load()
        policy = TierPolicy(
            configs: policy.configs.map {
                TierConfig(tier: $0.tier, model: "mutated", effort: $0.effort, maxConcurrent: $0.maxConcurrent, fallbackModel: $0.fallbackModel)
            },
            provider: policy.provider
        )
        try store.save(policy)
        XCTAssertEqual(store.load().model(for: .meta), "mutated")

        let reset = try store.resetToDefaults()
        XCTAssertNil(reset.model(for: .meta))
        XCTAssertNil(store.load().model(for: .meta))
    }

    func testFallbackSwitchesModel() {
        let policy = TierPolicy.defaultPolicy
        let switched = policy.withFallback(for: .meta)
        // meta 는 fallback(claude-opus-4.8) 이 모델로 승격된다.
        XCTAssertEqual(switched.model(for: .meta), "claude-opus-4.8")
        XCTAssertNil(switched.config(for: .meta)?.fallbackModel)
        // 다른 계층은 그대로(defer).
        XCTAssertNil(switched.model(for: .worker))
    }

    func testWorkerFieldDecodesFromLegacyPayload() throws {
        let json = Data(#"{"tier":"worker","effort":"medium","maxConcurrent":4}"#.utf8)
        let config = try JSONDecoder().decode(TierConfig.self, from: json)
        XCTAssertNil(config.worker)
    }

    func testWorkerFieldRoundTrip() throws {
        let config = TierConfig(tier: .worker, effort: "medium", maxConcurrent: 4, worker: "grok")
        let decoded = try JSONDecoder().decode(TierConfig.self, from: try JSONEncoder().encode(config))
        XCTAssertEqual(decoded.worker, "grok")
    }

    func testFallbackPreservesWorker() {
        let policy = TierPolicy(
            configs: [
                TierConfig(
                    tier: .worker,
                    model: "grok-code",
                    effort: "medium",
                    maxConcurrent: 4,
                    fallbackModel: "grok-4",
                    worker: "grok"
                ),
            ],
            provider: "grok"
        )
        let switched = policy.withFallback(for: .worker)
        XCTAssertEqual(switched.config(for: .worker)?.worker, "grok")
        XCTAssertEqual(switched.model(for: .worker), "grok-4")
    }

    func testFallbackNoOpWhenMissing() {
        let noFallback = TierConfig(tier: .meta, model: "m", effort: "high", maxConcurrent: 1, fallbackModel: nil)
        let policy = TierPolicy(configs: [noFallback], provider: "kiro")
        let result = policy.withFallback(for: .meta)
        XCTAssertEqual(result.model(for: .meta), "m")
    }

    func testResolveTierFromPrompt() {
        XCTAssertEqual(TierResolver.resolveTier(fromPrompt: "이 태스크를 설계하고 분해해줘"), .coordinator)
        XCTAssertEqual(TierResolver.resolveTier(fromPrompt: "전체 아키텍처를 판단해줘"), .coordinator)
        XCTAssertEqual(TierResolver.resolveTier(fromPrompt: "이 함수를 구현하고 리팩터해줘"), .worker)
        XCTAssertEqual(TierResolver.resolveTier(fromPrompt: "lint 오류를 확인하고 테스트를 검증해줘"), .verifier)
        XCTAssertEqual(TierResolver.resolveTier(fromPrompt: "아무 맥락 없는 문장"), .worker)
    }
}
