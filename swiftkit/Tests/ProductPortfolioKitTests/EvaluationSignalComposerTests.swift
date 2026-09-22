import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("Evaluation signal composer")
struct EvaluationSignalComposerTests {
    @Test("notarized install scores higher sellability than unsigned")
    func notarizedSellsHigher() throws {
        let base = EvaluationSignalBundle(
            slug: "demo-app",
            sales: .init(
                classification: "product-candidate",
                salesFieldsFilled: 3,
                hasRealScreenshot: true,
                hasCategories: true
            ),
            repo: .init(
                exists: true,
                hasTests: true,
                hasPackaging: true,
                hasCliIdentity: true,
                hasLicense: true
            ),
            install: .init(installed: true, built: true, auditState: "passed")
        )
        var unsigned = base
        unsigned.hardenedRuntime = true
        unsigned.notarized = false
        var notarized = base
        notarized.hardenedRuntime = true
        notarized.notarized = true

        let low = try EvaluationSignalComposer.score(from: unsigned)
        let high = try EvaluationSignalComposer.score(from: notarized)
        #expect(high.sellability - low.sellability >= 1.5)
        #expect(high.sellability > low.sellability)
    }

    @Test("unknown quality does not award a perfect score")
    func unknownQualityCapped() throws {
        let bare = EvaluationSignalBundle(slug: "bare-app", repo: .init(exists: true))
        let scores = try EvaluationSignalComposer.score(from: bare)
        #expect(scores.quality <= 3.0)
        #expect(scores.sellability <= 1.5)
        #expect(EvaluationSignalComposer.confidence(from: bare) < 0.5)
    }

    @Test("compose never overwrites a human evaluation")
    func preservesHuman() throws {
        let root = try temporaryEvaluations()
        let store = EvaluationStore(root: root)
        let human = try Evaluation(
            slug: "kept-app",
            evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            scores: try DimensionScores(sellability: 4, quality: 4, completeness: 4, differentiation: 4),
            strengths: ["사람이 씀"],
            improvements: [],
            summary: "수동 검토 완료"
        )
        try store.save(human)

        let bundle = EvaluationSignalBundle(
            slug: "kept-app",
            repo: .init(exists: true, hasTests: true),
            install: .init(installed: true),
            release: .init(hardenedRuntime: false, notarized: false)
        )
        let result = try EvaluationSignalComposer.compose(
            bundles: [bundle],
            into: store,
            refreshDrafts: true,
            dryRun: false
        )
        #expect(result.skipped == ["kept-app"])
        #expect(result.items.first?.action == "skip-manual")
        let loaded = try store.load(slug: "kept-app")
        #expect(loaded.current.summary == "수동 검토 완료")
        #expect(loaded.current.scores.sellability == 4)
    }

    @Test("compose creates draft and refreshes only signal drafts")
    func createsAndRefreshesDrafts() throws {
        let root = try temporaryEvaluations()
        let store = EvaluationStore(root: root)
        let first = EvaluationSignalBundle(
            slug: "draft-app",
            sales: .init(classification: "product-candidate", salesFieldsFilled: 0),
            repo: .init(exists: true, hasTests: false, hasLicense: false),
            install: .init(installed: false)
        )
        let created = try EvaluationSignalComposer.compose(
            bundles: [first],
            into: store,
            refreshDrafts: false,
            dryRun: false
        )
        #expect(created.created == ["draft-app"])
        let afterCreate = try store.load(slug: "draft-app")
        #expect(EvaluationSignalComposer.isDraftSummary(afterCreate.current.summary))
        #expect(!afterCreate.current.improvements.isEmpty)

        var second = first
        second.installed = true
        second.hasTests = true
        second.hasLicense = true
        second.hardenedRuntime = true
        second.notarized = true
        second.auditState = "passed"

        let skipped = try EvaluationSignalComposer.compose(
            bundles: [second],
            into: store,
            refreshDrafts: false,
            dryRun: false
        )
        #expect(skipped.skipped.contains("draft-app"))

        let refreshed = try EvaluationSignalComposer.compose(
            bundles: [second],
            into: store,
            refreshDrafts: true,
            dryRun: false
        )
        #expect(refreshed.updated == ["draft-app"])
        let after = try store.load(slug: "draft-app")
        #expect(after.current.scores.sellability >= 3.0)
        #expect(after.history.count == 1)
    }

    @Test("two fixtures with same product card differ when install gates differ")
    func installGatesDiscriminate() throws {
        let card = EvaluationSignalBundle(
            slug: "a",
            sales: .init(
                classification: "product-candidate",
                salesFieldsFilled: 3,
                hasRealScreenshot: true,
                hasCategories: true
            ),
            repo: .init(
                exists: true,
                hasTests: true,
                hasPackaging: true,
                hasCliIdentity: true,
                hasLicense: false
            )
        )
        var missing = card
        missing.slug = "missing-app"
        missing.installed = false
        var ready = card
        ready.slug = "ready-app"
        ready.installed = true
        ready.hardenedRuntime = true
        ready.notarized = true
        ready.hasLicense = true
        ready.auditState = "passed"

        let low = try EvaluationSignalComposer.score(from: missing)
        let high = try EvaluationSignalComposer.score(from: ready)
        #expect(high.sellability - low.sellability >= 1.5)
        #expect(high.completeness > low.completeness)
        #expect(low.overallAverage + 0.5 < high.overallAverage)
    }

    @Test("store-ready candidate can reach 5.0 on every signal dimension")
    func fullSurfaceCanScorePerfect() throws {
        let bundle = EvaluationSignalBundle(
            slug: "ready-product",
            sales: .init(
                classification: "product-candidate",
                salesFieldsFilled: 3,
                hasRealScreenshot: true,
                hasCategories: true
            ),
            repo: .init(
                exists: true,
                hasTests: true,
                hasPackaging: true,
                hasCliIdentity: true,
                hasLicense: true
            ),
            install: .init(installed: true, built: true, staleInstall: false, auditState: "passed"),
            release: .init(hardenedRuntime: true, notarized: true, qualityLoopScore: 100)
        )
        let scores = try EvaluationSignalComposer.score(from: bundle)
        #expect(scores.sellability == 5.0)
        #expect(scores.quality == 5.0)
        #expect(scores.completeness == 5.0)
        #expect(scores.differentiation == 5.0)
    }

    @Test("affinity-only summary is a draft so compose can fill zeros")
    func affinityStubIsDraft() throws {
        #expect(EvaluationSignalComposer.isDraftSummary("agent-score-v1=100"))
        #expect(EvaluationSignalComposer.isManualSummary("수동 검토 완료 · agent-score-v1=100"))
        let root = try temporaryEvaluations()
        let store = EvaluationStore(root: root)
        let stub = try Evaluation(
            slug: "affinity-app",
            evaluatedAt: Date(timeIntervalSince1970: 1),
            scores: try DimensionScores(sellability: 0, quality: 0, completeness: 0, differentiation: 0),
            strengths: [],
            improvements: [],
            summary: "agent-score-v1=100"
        )
        try store.save(stub)
        let bundle = EvaluationSignalBundle(
            slug: "affinity-app",
            sales: .init(
                classification: "product-candidate",
                salesFieldsFilled: 3,
                hasRealScreenshot: true,
                hasCategories: true
            ),
            repo: .init(
                exists: true,
                hasTests: true,
                hasPackaging: true,
                hasCliIdentity: true,
                hasLicense: true
            ),
            install: .init(installed: true, built: true),
            release: .init(hardenedRuntime: true, notarized: true, qualityLoopScore: 100)
        )
        let result = try EvaluationSignalComposer.compose(
            bundles: [bundle],
            into: store,
            refreshDrafts: true,
            dryRun: false
        )
        #expect(result.updated == ["affinity-app"])
        let loaded = try store.load(slug: "affinity-app")
        #expect(loaded.current.scores.sellability == 5.0)
        #expect(EvaluationSignalComposer.isDraftSummary(loaded.current.summary))
    }

    @Test("readiness treats signal-v1 as non-manual")
    func readinessDraftDetection() throws {
        let root = try temporaryEvaluations()
        let store = EvaluationStore(root: root)
        let bundle = EvaluationSignalBundle(
            slug: "sig-app",
            repo: .init(exists: true),
            install: .init(installed: true)
        )
        try store.save(try EvaluationSignalComposer.makeEvaluation(from: bundle))
        let url = root.appending(path: "sig-app.json")
        #expect(!ReadinessRecomputer.isManualEvaluation(at: url))
    }

    private func temporaryEvaluations() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "signal-compose-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private extension DimensionScores {
    var overallAverage: Double { average }
}
