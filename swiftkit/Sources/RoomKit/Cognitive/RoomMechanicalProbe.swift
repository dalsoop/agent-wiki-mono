import Foundation

/// Git 및 커널 기반의 기계적 인지 실측 프로브 (Mechanical Probe)
///
/// 에이전트의 자기 서술을 배제하고 결정론적 공식에 의해 driftScore와 RoomDelta를 산출한다.
public struct RoomMechanicalProbe: Sendable {

    /// 실측 데이터 주입 모델
    public struct Measurement: Sendable {
        public let actualTouchedFiles: [String]
        public let actualLinesAdded: Int
        public let actualLinesDeleted: Int
        public let actualDurationSec: Double
        public let detectedImports: [String]
        public let isBreakGlass: Bool
        public let breakGlassReason: String?

        public init(
            actualTouchedFiles: [String],
            actualLinesAdded: Int,
            actualLinesDeleted: Int,
            actualDurationSec: Double,
            detectedImports: [String] = [],
            isBreakGlass: Bool = false,
            breakGlassReason: String? = nil
        ) {
            self.actualTouchedFiles = actualTouchedFiles
            self.actualLinesAdded = actualLinesAdded
            self.actualLinesDeleted = actualLinesDeleted
            self.actualDurationSec = actualDurationSec
            self.detectedImports = detectedImports
            self.isBreakGlass = isBreakGlass
            self.breakGlassReason = breakGlassReason
        }
    }

    public init() {}

    /// 선행 가계산(Precompute)과 기계 계측값(Measurement)을 대조하여 RoomDelta를 산출한다.
    public func evaluate(
        precompute: RoomPrecompute,
        measurement: Measurement
    ) -> RoomDelta {
        let pFiles = Set(precompute.targets)
        let aFiles = Set(measurement.actualTouchedFiles)

        let driftFile = calculateFileDrift(pFiles: pFiles, aFiles: aFiles)
        let actualTotalLines = measurement.actualLinesAdded + measurement.actualLinesDeleted
        let driftLines = calculateLinesDrift(predicted: precompute.estimatedLines, actualTotal: actualTotalLines)
        let driftTime = calculateTimeDrift(predicted: precompute.estimatedDurationSec, actual: measurement.actualDurationSec)

        let couplingResult = calculateCouplingDrift(
            declared: precompute.declaredImports,
            detected: measurement.detectedImports
        )

        let weightedScore = (driftFile * 40.0) + (driftLines * 25.0) + (driftTime * 15.0) + (couplingResult.drift * 20.0)
        let driftScore = min(100.0, max(0.0, weightedScore))

        let verdict = determineVerdict(driftScore: driftScore, isBreakGlass: measurement.isBreakGlass)
        let unauthorizedFileCount = aFiles.subtracting(pFiles).count
        let requiresFalsification = shouldRequireFalsification(
            driftScore: driftScore,
            unauthorizedFileCount: unauthorizedFileCount
        )

        return RoomDelta(
            roomID: precompute.roomID,
            tenantID: precompute.tenantID,
            commitmentHash: precompute.commitmentHash,
            actualTouchedFiles: measurement.actualTouchedFiles,
            actualLinesAdded: measurement.actualLinesAdded,
            actualLinesDeleted: measurement.actualLinesDeleted,
            actualDurationSec: measurement.actualDurationSec,
            unauthorizedImports: couplingResult.unauthorized,
            driftFile: driftFile,
            driftLines: driftLines,
            driftTime: driftTime,
            driftCoupling: couplingResult.drift,
            driftScore: driftScore,
            verdict: verdict,
            requiresFalsificationSynapse: requiresFalsification,
            isBreakGlass: measurement.isBreakGlass,
            breakGlassReason: measurement.breakGlassReason
        )
    }

    // MARK: - Private Metrics Calculators

    private func calculateFileDrift(pFiles: Set<String>, aFiles: Set<String>) -> Double {
        guard !pFiles.isEmpty || !aFiles.isEmpty else { return 0.0 }

        let intersection = pFiles.intersection(aFiles)
        let unauthorized = aFiles.subtracting(pFiles) // 미신고 수정 (2.0x 페널티)
        let unexecuted = pFiles.subtracting(aFiles)   // 계획했으나 안 건드림 (0.5x 페널티)

        let weightedUnion = Double(intersection.count) + (Double(unauthorized.count) * 2.0) + (Double(unexecuted.count) * 0.5)
        guard weightedUnion > 0 else { return 0.0 }
        let similarity = Double(intersection.count) / weightedUnion
        return max(0.0, min(1.0, 1.0 - similarity))
    }

    private func calculateLinesDrift(predicted: Int, actualTotal: Int) -> Double {
        let lineDenom = max(predicted, actualTotal, 10)
        return min(1.0, Double(abs(predicted - actualTotal)) / Double(lineDenom))
    }

    private func calculateTimeDrift(predicted: Int, actual: Double) -> Double {
        let predictedSec = Double(predicted)
        let timeDenom = max(predictedSec, actual, 10.0)
        return min(1.0, abs(predictedSec - actual) / timeDenom)
    }

    private func calculateCouplingDrift(
        declared: [String],
        detected: [String]
    ) -> (drift: Double, unauthorized: [String]) {
        let declaredSet = Set(declared)
        let detectedSet = Set(detected)
        let unauthorizedImports = Array(detectedSet.subtracting(declaredSet)).sorted()
        let totalImportScope = max(declaredSet.count + unauthorizedImports.count, 1)
        let driftCoupling = min(1.0, Double(unauthorizedImports.count) / Double(totalImportScope))
        return (driftCoupling, unauthorizedImports)
    }

    private func determineVerdict(driftScore: Double, isBreakGlass: Bool) -> CognitiveVerdict {
        guard !isBreakGlass else { return .bypassed }
        switch driftScore {
        case ...15.0:
            return .pass
        case 15.01...35.0:
            return .warning
        default:
            return .breach
        }
    }

    private func shouldRequireFalsification(driftScore: Double, unauthorizedFileCount: Int) -> Bool {
        let isBreachLevel = driftScore >= 35.0
        let hasUnauthorizedScopeLeak = unauthorizedFileCount > 0
        let isElevatedDrift = driftScore >= 25.0
        let isScopeViolation = hasUnauthorizedScopeLeak && isElevatedDrift
        return isBreachLevel || isScopeViolation
    }
}
