import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("Readiness recompute")
struct ReadinessRecomputerTests {
    @Test("score uses role length sales manual-eval screenshots")
    func scoreSignals() {
        #expect(
            ReadinessRecomputer.score(
                from: .init(
                    roleLength: 0,
                    salesFieldCount: 0,
                    hasEvaluation: false,
                    hasManualEvaluation: false,
                    hasScreenshots: false,
                    hasPackaging: false
                )
            ) == 0
        )
        // batch-seed eval does not add points
        #expect(
            ReadinessRecomputer.score(
                from: .init(
                    roleLength: 50,
                    salesFieldCount: 3,
                    hasEvaluation: true,
                    hasManualEvaluation: false,
                    hasScreenshots: false,
                    hasPackaging: true
                )
            ) == 3
        ) // role2 + sales1
        #expect(
            ReadinessRecomputer.score(
                from: .init(
                    roleLength: 50,
                    salesFieldCount: 3,
                    hasEvaluation: true,
                    hasManualEvaluation: true,
                    hasScreenshots: false,
                    hasPackaging: false
                )
            ) == 4
        )
        #expect(
            ReadinessRecomputer.score(
                from: .init(
                    roleLength: 80,
                    salesFieldCount: 3,
                    hasEvaluation: true,
                    hasManualEvaluation: true,
                    hasScreenshots: true,
                    hasPackaging: true
                )
            ) == 5
        )
    }

    @Test("dry-run reports changes without writing")
    func dryRun() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProductStore(rootDirectory: root)
        try store.add(
            try Product(
                names: .init(slug: "sample-app", nameKo: "샘플 앱 이름", nameEn: "Sample App"),
                pitch: .init(
                    role: "반복 업무를 줄여주는 도구입니다",
                    classification: .productCandidate,
                    buyerPersona: "macOS 생산성 도구를 사는 1인 사업가",
                    salesAngle: "설치 즉시 바로 쓰는 macOS 앱으로 시간을 아낀다",
                    categories: ["tools"],
                    priceIdea: "베타 무료 · 정식 가격 미정"
                ),
                surface: .init(readiness: 4, screenshotPaths: [])
            )
        )
        let evals = root.appendingPathComponent("evaluations", isDirectory: true)
        try FileManager.default.createDirectory(at: evals, withIntermediateDirectories: true)
        // batch-seed style summary — should not count as manual
        let batch = """
        {"current":{"summary":"batch-seed v1 · readiness=4","slug":"sample-app"}}
        """
        try Data(batch.utf8).write(
            to: evals.appendingPathComponent("sample-app.json")
        )

        let result = try ReadinessRecomputer.recompute(
            in: store,
            options: .init(dryRun: true, writeSnapshot: false)
        )
        #expect(result.dryRun)
        #expect(result.changed == 1)
        #expect(result.changes.first?.from == 4)
        // role ~18 → +1, sales +1, batch eval +0 = 2
        #expect(result.changes.first?.to == 2)
        #expect(result.changes.first?.signals.hasManualEvaluation == false)
        #expect(try store.show(slug: "sample-app").readiness == 4)
    }

    @Test("apply writes readiness and optional snapshot")
    func applyWithSnapshot() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProductStore(rootDirectory: root)
        try store.add(
            try Product(
                names: .init(slug: "other-app", nameKo: "다른", nameEn: "Other"),
                pitch: .init(
                    role: "",
                    classification: .internalTool,
                    buyerPersona: "",
                    salesAngle: "",
                    categories: [],
                    priceIdea: ""
                ),
                surface: .init(readiness: 4, screenshotPaths: [])
            )
        )

        let result = try ReadinessRecomputer.recompute(
            in: store,
            options: .init(dryRun: false, writeSnapshot: true)
        )
        #expect(!result.dryRun)
        #expect(result.changed == 1)
        #expect(result.changes.first?.to == 0)
        #expect(try store.show(slug: "other-app").readiness == 0)
        #expect(result.snapshotPath != nil)
        if let snapshotPath = result.snapshotPath {
            #expect(FileManager.default.fileExists(atPath: snapshotPath))
        }
    }

    @Test("packaging detection under apps root")
    func packaging() throws {
        let base = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: base) }
        let apps = base.appendingPathComponent("apps", isDirectory: true)
        let packaging = apps
            .appendingPathComponent("demo-swift")
            .appendingPathComponent("Packaging", isDirectory: true)
        try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)
        #expect(
            ReadinessRecomputer.packagingExists(for: "demo-swift", appsRoot: apps)
        )
        #expect(
            !ReadinessRecomputer.packagingExists(for: "missing-app", appsRoot: apps)
        )
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
