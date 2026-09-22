import Foundation

/// 설치본·레포·router 신호 → 평가 초안 (`provenance=signal-v1`).
public enum EvaluationSignalComposer {
    public static let provenancePrefix = "signal-v1"
    public static let legacyBatchPrefix = "batch-seed"
    /// 신호·readiness 공통 단위 만점(0…5). PES GUI 0…100 변환은 앱 CLI 브리지가 담당.
    public static var unitScaleMax: Double { ScoreScale.signalMax }

    public static func isDraftSummary(_ summary: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains(provenancePrefix) || lower.contains(legacyBatchPrefix) { return true }
        // score-agent 만 찍힌 스텁은 사람 평가가 아니다. 4차원을 0으로 고정하면 안 된다.
        return trimmed.range(of: #"^agent-score-v1=\d+$"#, options: .regularExpression) != nil
    }

    public static func isManualSummary(_ summary: String) -> Bool {
        !isDraftSummary(summary)
    }

    public static func confidence(from bundle: EvaluationSignalBundle) -> Double {
        EvaluationSignalScoring.confidence(from: bundle)
    }

    public static func score(from bundle: EvaluationSignalBundle) throws -> DimensionScores {
        try EvaluationSignalScoring.score(from: bundle)
    }

    public static func strengths(from bundle: EvaluationSignalBundle) -> [String] {
        EvaluationSignalNarrative.strengths(from: bundle)
    }

    public static func improvements(from bundle: EvaluationSignalBundle) throws -> [Improvement] {
        try EvaluationSignalNarrative.improvements(from: bundle)
    }

    public static func summary(from bundle: EvaluationSignalBundle, confidence: Double) -> String {
        EvaluationSignalNarrative.summary(from: bundle, confidence: confidence)
    }

    public static func makeEvaluation(
        from bundle: EvaluationSignalBundle,
        evaluatedAt: Date = Date()
    ) throws -> Evaluation {
        let confidence = confidence(from: bundle)
        let scores = try score(from: bundle)
        return try Evaluation(
            slug: bundle.slug,
            evaluatedAt: evaluatedAt,
            scores: scores,
            strengths: strengths(from: bundle),
            improvements: try improvements(from: bundle),
            summary: summary(from: bundle, confidence: confidence)
        )
    }

    /// `human`/`agent-review` 요약은 덮어쓰지 않는다. draft(`signal-v1`·`batch-seed`)만 refresh.
    public static func compose(
        bundles: [EvaluationSignalBundle],
        into store: EvaluationStore,
        refreshDrafts: Bool = false,
        dryRun: Bool = false,
        minConfidence: Double = 0
    ) throws -> SignalComposeResult {
        var created: [String] = []
        var updated: [String] = []
        var skipped: [String] = []
        var items: [SignalComposeItem] = []

        for bundle in bundles.sorted(by: { $0.slug < $1.slug }) {
            let confidence = confidence(from: bundle)
            if confidence < minConfidence {
                skipped.append(bundle.slug)
                continue
            }
            let decision = try EvaluationSignalComposeRun.decide(
                bundle: bundle,
                store: store,
                refreshDrafts: refreshDrafts,
                dryRun: dryRun
            )
            try EvaluationSignalComposeRun.apply(decision, store: store, dryRun: dryRun)
            switch decision.kind {
            case .create:
                created.append(bundle.slug)
            case .update:
                updated.append(bundle.slug)
            case .skip:
                skipped.append(bundle.slug)
            }
            items.append(
                EvaluationSignalComposeRun.item(
                    slug: bundle.slug,
                    decision: decision,
                    confidence: confidence
                )
            )
        }

        return SignalComposeResult(
            created: created,
            updated: updated,
            skipped: skipped,
            dryRun: dryRun,
            items: items
        )
    }
}
