import Foundation

/// 신호 묶음 → 강점·개선점·요약 문구.
enum EvaluationSignalNarrative {
    static func strengths(from bundle: EvaluationSignalBundle) -> [String] {
        var items: [String] = []
        if bundle.hasTests { items.append("Tests 타깃이 있다") }
        if bundle.installed, bundle.staleInstall == false {
            items.append("설치본이 있다")
        }
        if bundle.hardenedRuntime == true { items.append("Hardened Runtime 활성") }
        if bundle.notarized == true { items.append("공증(stapler) 통과") }
        if bundle.auditState == "passed" { items.append("fleet audit passed") }
        if let q = bundle.qualityLoopScore, q >= 90 {
            items.append("quality-loop \(Int(q))점")
        }
        return items
    }

    static func improvements(from bundle: EvaluationSignalBundle) throws -> [Improvement] {
        var items: [Improvement] = []
        try appendInstallGaps(from: bundle, into: &items)
        try appendQualityGaps(from: bundle, into: &items)
        return items
    }

    static func summary(from bundle: EvaluationSignalBundle, confidence: Double) -> String {
        let audit = bundle.auditState ?? "n/a"
        let installed = bundle.installed ? 1 : 0
        return
            "\(EvaluationSignalComposer.provenancePrefix) · confidence=\(String(format: "%.2f", confidence)) · installed=\(installed) · hardened=\(flag(bundle.hardenedRuntime)) · notarized=\(flag(bundle.notarized)) · audit=\(audit)"
    }

    private static func appendInstallGaps(
        from bundle: EvaluationSignalBundle,
        into items: inout [Improvement]
    ) throws {
        if !bundle.installed {
            items.append(
                try Improvement(
                    text: "설치본이 없다",
                    severity: .high,
                    suggestedAction: "swift-app-router ship \(bundle.slug)"
                )
            )
        }
        if bundle.installed, bundle.hardenedRuntime == false {
            items.append(
                try Improvement(
                    text: "Hardened Runtime 이 꺼져 있다",
                    severity: .critical,
                    suggestedAction: "서명 옵션에 --options runtime 후 재빌드"
                )
            )
        }
        if bundle.installed, bundle.notarized == false {
            items.append(
                try Improvement(
                    text: "공증되지 않았다 — 타 Mac Gatekeeper 차단 가능",
                    severity: .critical,
                    suggestedAction: "AppBuildManager notarize <App.app>"
                )
            )
        }
        if bundle.installed, bundle.hardenedRuntime == nil, bundle.notarized == nil {
            items.append(
                try Improvement(
                    text: "릴리스 게이트(서명·공증) 미스캔",
                    severity: .medium,
                    suggestedAction: "signal-compose --probe-release"
                )
            )
        }
        if !bundle.hasLicense {
            items.append(
                try Improvement(
                    text: "LICENSE 파일이 없다",
                    severity: .high,
                    suggestedAction: "앱 디렉터리에 LICENSE 추가"
                )
            )
        }
    }

    private static func appendQualityGaps(
        from bundle: EvaluationSignalBundle,
        into items: inout [Improvement]
    ) throws {
        if !bundle.hasTests {
            items.append(
                try Improvement(
                    text: "Tests 타깃이 없다",
                    severity: .medium,
                    suggestedAction: "swift test 가능한 테스트 추가"
                )
            )
        }
        if bundle.auditState == "blocked" {
            items.append(
                try Improvement(
                    text: "fleet audit 이 blocked 상태다",
                    severity: .high,
                    suggestedAction: "app-fleet-quality-auditor audit --root … --json"
                )
            )
        }
        if let q = bundle.qualityLoopScore, q < 90 {
            items.append(
                try Improvement(
                    text: "quality-loop 점수 \(Int(q)) < 90",
                    severity: .medium,
                    suggestedAction: "app-quality-loop 로 갭 해소 후 evidence 갱신"
                )
            )
        }
        if bundle.staleInstall {
            items.append(
                try Improvement(
                    text: "설치본이 소스보다 오래됐다",
                    severity: .medium,
                    suggestedAction: "swift-app-router ship \(bundle.slug)"
                )
            )
        }
    }

    private static func flag(_ value: Bool?) -> String {
        switch value {
        case true?: return "1"
        case false?: return "0"
        case nil: return "?"
        }
    }
}
