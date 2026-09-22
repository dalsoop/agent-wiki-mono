import Foundation

/// 신호 묶음 → 4차원 점수·confidence. 카피 길이는 쓰지 않는다.
enum EvaluationSignalScoring {
    static func confidence(from bundle: EvaluationSignalBundle) -> Double {
        var value = 0.15
        if bundle.repoExists { value += 0.15 }
        if bundle.auditState != nil || bundle.installed || bundle.built { value += 0.2 }
        if bundle.installed { value += 0.1 }
        if bundle.hardenedRuntime != nil { value += 0.15 }
        if bundle.notarized != nil { value += 0.15 }
        if bundle.qualityLoopScore != nil { value += 0.1 }
        return min(1.0, (value * 100).rounded() / 100)
    }

    static func score(from bundle: EvaluationSignalBundle) throws -> DimensionScores {
        try DimensionScores(
            sellability: round1(sellability(from: bundle)),
            quality: round1(quality(from: bundle)),
            completeness: round1(completeness(from: bundle)),
            differentiation: round1(differentiation(from: bundle))
        )
    }

    static func completeness(from bundle: EvaluationSignalBundle) -> Double {
        var value = 0.0
        if bundle.repoExists { value += 1.0 }
        if bundle.hasTests { value += 1.0 }
        if bundle.hasPackaging { value += 0.5 }
        if bundle.hasCliIdentity { value += 0.5 }
        if bundle.installed {
            value += bundle.staleInstall ? 0.5 : 1.0
        }
        if bundle.built { value += 0.5 }
        if bundle.notarized == true { value += 0.5 }
        if bundle.installed, bundle.staleInstall == false,
           bundle.hardenedRuntime == true || bundle.auditState == "passed" {
            value += 0.5
        }
        if bundle.completenessLabel == "stub" || bundle.auditState == "blocked" {
            value = min(value, 2.0)
        }
        return clamp(value)
    }

    static func quality(from bundle: EvaluationSignalBundle) -> Double {
        if let loop = bundle.qualityLoopScore {
            return clamp(loop / 100.0 * 5.0)
        }
        var value = 2.0
        switch bundle.auditState {
        case "passed": value = 4.0
        case "warning": value = 3.0
        case "blocked": value = 1.5
        case "rolled-back": value = 1.0
        default: break
        }
        if bundle.hasTests { value += 0.5 }
        if bundle.notarized == true { value += 0.5 }
        if bundle.installed, bundle.hasTests,
           bundle.hardenedRuntime == true, bundle.notarized == true {
            value = max(value, 5.0)
        }
        if !bundle.installed, bundle.repoExists {
            value = min(value, 3.0)
        }
        return clamp(value)
    }

    static func sellability(from bundle: EvaluationSignalBundle) -> Double {
        var value = bundle.installed ? 0.5 : 0.0
        if bundle.hardenedRuntime == true { value += 1.0 }
        if bundle.notarized == true { value += 1.5 }
        if bundle.hasLicense { value += 0.5 }
        if bundle.salesFieldsFilled >= 3 { value += 0.5 }
        if bundle.hasRealScreenshot, bundle.salesFieldsFilled >= 3, bundle.notarized == true {
            value += 1.0
        }
        if !bundle.installed {
            value = min(value, 1.5)
        }
        return clamp(value)
    }

    static func differentiation(from bundle: EvaluationSignalBundle) -> Double {
        var value = 1.5
        if bundle.classification == "product-candidate" { value += 0.5 }
        if bundle.hasRealScreenshot { value += 0.5 }
        if bundle.hasCategories { value += 0.3 }
        if let loop = bundle.qualityLoopScore, loop >= 80 {
            value += 0.5
        } else if bundle.notarized == true, bundle.hasTests, bundle.hasRealScreenshot {
            value += 0.5
        }
        if bundle.notarized == true, bundle.hasCliIdentity { value += 1.0 }
        if bundle.salesFieldsFilled >= 3, bundle.hasRealScreenshot { value += 0.7 }
        if bundle.classification == "internal-tool" {
            value = min(value, 2.0)
        }
        return clamp(value)
    }

    private static func clamp(_ value: Double) -> Double {
        min(5, max(0, value))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
