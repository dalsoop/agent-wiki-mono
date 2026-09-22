import Foundation

/// compose 한 건의 create/update/skip 판정. 사람 평가는 덮지 않는다.
enum EvaluationSignalComposeRun {
    struct Decision {
        var action: String
        var kind: Kind
        var evaluation: Evaluation
        var display: Evaluation
    }

    enum Kind {
        case create
        case update
        case skip
    }

    static func decide(
        bundle: EvaluationSignalBundle,
        store: EvaluationStore,
        refreshDrafts: Bool,
        dryRun: Bool
    ) throws -> Decision {
        let evaluation = try EvaluationSignalComposer.makeEvaluation(from: bundle)
        guard store.exists(slug: bundle.slug) else {
            return Decision(
                action: dryRun ? "would-create" : "create",
                kind: .create,
                evaluation: evaluation,
                display: evaluation
            )
        }
        let previous = try store.load(slug: bundle.slug)
        if EvaluationSignalComposer.isDraftSummary(previous.current.summary) {
            if refreshDrafts {
                return Decision(
                    action: dryRun ? "would-update" : "update",
                    kind: .update,
                    evaluation: evaluation,
                    display: evaluation
                )
            }
            return Decision(
                action: "skip-existing-draft",
                kind: .skip,
                evaluation: evaluation,
                display: previous.current
            )
        }
        return Decision(
            action: "skip-manual",
            kind: .skip,
            evaluation: evaluation,
            display: previous.current
        )
    }

    static func apply(
        _ decision: Decision,
        store: EvaluationStore,
        dryRun: Bool
    ) throws {
        if dryRun { return }
        switch decision.kind {
        case .create, .update:
            try store.save(decision.evaluation)
        case .skip:
            break
        }
    }

    static func item(
        slug: String,
        decision: Decision,
        confidence: Double
    ) -> SignalComposeItem {
        SignalComposeItem(
            slug: slug,
            action: decision.action,
            overallScore: decision.display.overallScore,
            confidence: confidence,
            scores: decision.display.scores,
            improvementCount: decision.display.improvements.count,
            summary: decision.display.summary
        )
    }
}
