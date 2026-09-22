import Foundation
import Testing
@testable import ProductPortfolioKit

@Suite("Quality loop evidence loader")
struct QualityLoopEvidenceLoaderTests {
    @Test("score_app categories weights produce 0-100 total")
    func weightedCategories() throws {
        let json = """
        {
          "app": "apps/demo-swift",
          "categories": {
            "correctness": {"score": 100, "evidence": ["ok"]},
            "tests": {"score": 80, "evidence": ["ok"]},
            "ux": {"score": 80, "evidence": ["ok"]},
            "architecture": {"score": 80, "evidence": ["ok"]},
            "integration": {"score": 80, "evidence": ["ok"]},
            "docs_ops": {"score": 80, "evidence": ["ok"]},
            "git_hygiene": {"score": 100, "evidence": ["ok"]}
          }
        }
        """
        let score = try #require(QualityLoopEvidenceLoader.score(from: Data(json.utf8)))
        // 25*100 + 20*80 + 15*80 + 15*80 + 10*80 + 10*80 + 5*100 = 2500+1600+1200+1200+800+800+500 = 8600 / 100 = 86
        #expect(abs(score - 86) < 0.01)
    }

    @Test("direct score field is accepted")
    func directScore() throws {
        let json = #"{"score": 92.5, "app": "apps/x-swift"}"#
        #expect(QualityLoopEvidenceLoader.score(from: Data(json.utf8)) == 92.5)
    }

    @Test("directory maps slug files into score dict")
    func loadDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "ql-ev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try #"{"score": 91}"#.write(
            to: dir.appending(path: "ready-app-swift.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "app": "apps/other-tool-swift",
          "categories": {
            "correctness": {"score": 70, "evidence": ["e"]},
            "tests": {"score": 70, "evidence": ["e"]},
            "ux": {"score": 70, "evidence": ["e"]},
            "architecture": {"score": 70, "evidence": ["e"]},
            "integration": {"score": 70, "evidence": ["e"]},
            "docs_ops": {"score": 70, "evidence": ["e"]},
            "git_hygiene": {"score": 70, "evidence": ["e"]}
          }
        }
        """.write(
            to: dir.appending(path: "other-tool-swift-evidence.json"),
            atomically: true,
            encoding: .utf8
        )

        let map = QualityLoopEvidenceLoader.loadScores(from: dir)
        #expect(map["ready-app-swift"] == 91)
        #expect(map["other-tool-swift"] == 70)
    }

    @Test("quality loop score drives quality dimension")
    func qualityDimensionFromLoop() throws {
        var low = EvaluationSignalBundle(
            slug: "a",
            repo: .init(exists: true, hasTests: true),
            install: .init(installed: true)
        )
        low.qualityLoopScore = 40
        var high = low
        high.qualityLoopScore = 95
        let lowScores = try EvaluationSignalComposer.score(from: low)
        let highScores = try EvaluationSignalComposer.score(from: high)
        #expect(lowScores.quality == 2.0)
        #expect(highScores.quality == 4.8) // 95/100*5 = 4.75 → round1 4.8
        #expect(highScores.quality > lowScores.quality)
    }
}
