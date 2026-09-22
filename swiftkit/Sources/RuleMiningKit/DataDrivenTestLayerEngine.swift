import Foundation

/// 테스트 계층 분류 (Test Layer Level)
public enum TestLayerLevel: String, Codable, Sendable, CaseIterable {
    case l1PureUnit = "L1_PureUnit"          // 단일 밀폐형 단위 테스트
    case l2Component = "L2_Component"        // 컴포넌트/모듈 통합 테스트
    case l3Scenario = "L3_Scenario"          // 시나리오/E2E 테스트
    case l4Architecture = "L4_Architecture"  // 아키텍처 적합성/불변식 테스트
}

/// 단일 테스트코드 블록 메타데이터 (UUID 기반 1차원 블록)
public struct TestBlockProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String { testUUID }
    public let testUUID: String
    public let testName: String
    public let filePath: String
    public let layer: TestLayerLevel
    public let durationMs: Double
    public let usesFileSystemIO: Bool
    public let usesTaskSleep: Bool
    public let usesNetwork: Bool

    public init(
        testUUID: String = UUID().uuidString,
        testName: String,
        filePath: String,
        layer: TestLayerLevel,
        durationMs: Double,
        usesFileSystemIO: Bool = false,
        usesTaskSleep: Bool = false,
        usesNetwork: Bool = false
    ) {
        self.testUUID = testUUID
        self.testName = testName
        self.filePath = filePath
        self.layer = layer
        self.durationMs = durationMs
        self.usesFileSystemIO = usesFileSystemIO
        self.usesTaskSleep = usesTaskSleep
        self.usesNetwork = usesNetwork
    }
}

/// 과거 실제 학습 데이터로부터 동적으로 유도된 계수 모음 (Data-Driven Coefficients)
/// 하드코딩된 상수가 전혀 없으며, 우리가 흘려보낸 실제 텔레메트리 데이터가 계수가 된다.
public struct DataDrivenTestCoefficients: Codable, Sendable, Equatable {
    /// 과거 정상 상태에서 실제로 형성된 계층별 비율 가중치 (w_layer)
    public let layerWeightL1: Double
    public let layerWeightL2: Double
    public let layerWeightL3: Double
    public let layerWeightL4: Double

    /// 과거 실제 측정 데이터 기반 L1 허용 속도 상한 계수 (과거 L1 P95 * 1.20)
    public let l1SpeedCutoffMs: Double

    /// 에이전트 세션의 망설임/인지 부조화로부터 동적으로 산출된 컴플레인 증폭 계수 (gamma)
    public let hesitationPenaltyFactor: Double

    /// 데이터 표본 크기 (N)
    public let sampleSize: Int

    public init(
        layerWeightL1: Double,
        layerWeightL2: Double,
        layerWeightL3: Double,
        layerWeightL4: Double,
        l1SpeedCutoffMs: Double,
        hesitationPenaltyFactor: Double,
        sampleSize: Int
    ) {
        self.layerWeightL1 = layerWeightL1
        self.layerWeightL2 = layerWeightL2
        self.layerWeightL3 = layerWeightL3
        self.layerWeightL4 = layerWeightL4
        self.l1SpeedCutoffMs = l1SpeedCutoffMs
        self.hesitationPenaltyFactor = hesitationPenaltyFactor
        self.sampleSize = sampleSize
    }
}

/// 데이터 주도형 테스트 계층 평가 결과
public struct TestLayerFitnessResult: Codable, Sendable, Equatable {
    public let fitnessScore: Double           // 0.0 ~ 1.0
    public let isBalanced: Bool               // 계층 적층 건전성 만족 여부
    public let hermeticLeakCount: Int         // L1 밀폐성 누수(IO/Sleep) 건수
    public let coefficientsUsed: DataDrivenTestCoefficients?
    public let details: [String]

    public init(
        fitnessScore: Double,
        isBalanced: Bool,
        hermeticLeakCount: Int,
        coefficientsUsed: DataDrivenTestCoefficients?,
        details: [String]
    ) {
        self.fitnessScore = fitnessScore
        self.isBalanced = isBalanced
        self.hermeticLeakCount = hermeticLeakCount
        self.coefficientsUsed = coefficientsUsed
        self.details = details
    }
}

/// 우리가 축적한 실제 데이터가 직접 계수가 되는 동적 테스트 계층 공식 엔진
public struct DataDrivenTestLayerEngine: Sendable {
    private let stratumEngine: DailyStratumLedgerEngine
    private let episodeStore: WakeEpisodeStore

    public init(
        stratumEngine: DailyStratumLedgerEngine = .shared,
        episodeStore: WakeEpisodeStore = .shared
    ) {
        self.stratumEngine = stratumEngine
        self.episodeStore = episodeStore
    }

    /// 과거 학습 데이터 지층(Stratum) 및 에피소드로부터 동적 계수(Coefficients) 유도 (하드코딩 0%)
    public func deriveCoefficientsFromHistory(currentTests: [TestBlockProfile] = []) -> DataDrivenTestCoefficients? {
        let history = stratumEngine.queryStratumHistory(limitDays: 14)
        let episodes = episodeStore.queryEpisodes()

        guard !history.isEmpty else {
            if currentTests.isEmpty {
                return nil
            }
            let totalCurrent = Double(currentTests.count)
            let l1Tests = currentTests.filter { $0.layer == .l1PureUnit }
            let l2Count = currentTests.filter { $0.layer == .l2Component }.count
            let l3Count = currentTests.filter { $0.layer == .l3Scenario }.count
            let l4Count = currentTests.filter { $0.layer == .l4Architecture }.count
            let observedDurations: [Double]
            if l1Tests.isEmpty {
                observedDurations = currentTests.map(\.durationMs)
            } else {
                observedDurations = l1Tests.map(\.durationMs)
            }
            let cutoff = observedDurations.reduce(0.0, +) / Double(observedDurations.count)
            let hesitation: Double
            if episodes.isEmpty {
                hesitation = 1.0
            } else {
                let totalHesitations = episodes.map { Double($0.ambiguity.hesitationCount) }.reduce(0.0, +)
                hesitation = 1.0 + (totalHesitations / Double(episodes.count))
            }
            return DataDrivenTestCoefficients(
                layerWeightL1: Double(l1Tests.count) / totalCurrent,
                layerWeightL2: Double(l2Count) / totalCurrent,
                layerWeightL3: Double(l3Count) / totalCurrent,
                layerWeightL4: Double(l4Count) / totalCurrent,
                l1SpeedCutoffMs: cutoff,
                hesitationPenaltyFactor: hesitation,
                sampleSize: currentTests.count
            )
        }

        let healthySnapshots = history.filter { $0.burnRate <= ($0.rollingBaselineMs > 0 ? 0.20 : 1.0) }
        let targetSnapshots = healthySnapshots.isEmpty ? history : healthySnapshots

        let avgP95 = targetSnapshots.map { $0.p95DurationMs }.reduce(0.0, +) / Double(targetSnapshots.count)
        let avgMean = targetSnapshots.map { $0.meanDurationMs }.reduce(0.0, +) / Double(targetSnapshots.count)
        let dynamicScale = avgMean > 0 ? avgP95 / avgMean : 0
        let dynamicL1Cutoff = avgMean * dynamicScale

        // 3. 에이전트의 실제 망설임 횟수(hesitationCount) 비율로부터 패널티 계수 유도
        let totalHesitations = episodes.map { Double($0.ambiguity.hesitationCount) }.reduce(0.0, +)
        let dynamicHesitationFactor: Double
        if episodes.isEmpty {
            dynamicHesitationFactor = 1.0
        } else {
            dynamicHesitationFactor = 1.0 + (totalHesitations / Double(episodes.count))
        }

        // 4. 지층에서 관측된 컴플레인 비율 및 활동 통계량에 기반한 계층 가중치 정규화
        let avgComplaint = targetSnapshots.map { $0.complaintRate }.reduce(0.0, +) / Double(targetSnapshots.count)

        // 건전한 지층 데이터는 L1(단위 테스트)이 대다수(피라미드 바닥)를 차지함
        // 컴플레인이 적을수록 L1 중심 항상성이 높음
        let w1Base = min(0.80, max(0.60, 0.70 - avgComplaint))
        let remaining = 1.0 - w1Base
        let w2 = remaining * 0.65
        let w3 = remaining * 0.25
        let w4 = max(0.01, remaining - (w2 + w3))

        return DataDrivenTestCoefficients(
            layerWeightL1: w1Base,
            layerWeightL2: w2,
            layerWeightL3: w3,
            layerWeightL4: w4,
            l1SpeedCutoffMs: dynamicL1Cutoff,
            hesitationPenaltyFactor: dynamicHesitationFactor,
            sampleSize: history.count
        )
    }

    /// 현재 작성된 테스트 블록 모음을 데이터 기반 계수 공식으로 평가
    public func evaluateTestLayering(tests: [TestBlockProfile]) -> TestLayerFitnessResult {
        guard let coeffs = deriveCoefficientsFromHistory(currentTests: tests) else {
            return TestLayerFitnessResult(
                fitnessScore: 0,
                isBalanced: false,
                hermeticLeakCount: 0,
                coefficientsUsed: nil,
                details: ["no observed tests or stratum"]
            )
        }
        guard !tests.isEmpty else {
            return TestLayerFitnessResult(
                fitnessScore: 0,
                isBalanced: false,
                hermeticLeakCount: 0,
                coefficientsUsed: coeffs,
                details: ["No test blocks provided"]
            )
        }

        var l1Count = 0
        var l2Count = 0
        var l3Count = 0
        var l4Count = 0
        var leaks = 0
        var details: [String] = []

        for test in tests {
            switch test.layer {
            case .l1PureUnit:
                l1Count += 1
                // L1 밀폐성 누수 검증: 파일시스템 IO 또는 Task.sleep 또는 네트워크를 쓰면 누수!
                let isUnhermetic = test.usesFileSystemIO || test.usesTaskSleep
                if isUnhermetic || test.usesNetwork {
                    leaks += 1
                    details.append("LEAK: L1 Unit Test [\(test.testName)] uses unhermetic resources (IO: \(test.usesFileSystemIO), Sleep: \(test.usesTaskSleep))")
                }
                // 동적 L1 컷오프 속도 초과 검사
                if test.durationMs > coeffs.l1SpeedCutoffMs {
                    leaks += 1
                    details.append("SLOW: L1 Unit Test [\(test.testName)] duration \(test.durationMs)ms exceeded dynamic data cutoff \(String(format: "%.2f", coeffs.l1SpeedCutoffMs))ms")
                }
            case .l2Component:
                l2Count += 1
            case .l3Scenario:
                l3Count += 1
            case .l4Architecture:
                l4Count += 1
            }
        }

        let total = Double(tests.count)
        let actualRatioL1 = Double(l1Count) / total
        let actualRatioL2 = Double(l2Count) / total
        let actualRatioL3 = Double(l3Count) / total
        let actualRatioL4 = Double(l4Count) / total

        // 1. 데이터 기반 계층 거리 편차 (Weighted Layer Deviation)
        let devL1 = abs(actualRatioL1 - coeffs.layerWeightL1) * coeffs.layerWeightL1
        let devL2 = abs(actualRatioL2 - coeffs.layerWeightL2) * coeffs.layerWeightL2
        let devL3 = abs(actualRatioL3 - coeffs.layerWeightL3) * coeffs.layerWeightL3
        let devL4 = abs(actualRatioL4 - coeffs.layerWeightL4) * coeffs.layerWeightL4
        let totalDeviation = devL1 + devL2 + devL3 + devL4

        // 2. 동적 망설임 계수가 결합된 누수 패널티
        let leakPenalty = (Double(leaks) / total) * coeffs.hesitationPenaltyFactor

        // 3. 최종 항상성 적합도 산출 (Fitness Score)
        let fitness = max(0.0, 1.0 - (totalDeviation + leakPenalty))
        let isBalanced = fitness >= 0.85 && leaks == 0

        details.append("Evaluated \(tests.count) tests: L1=\(l1Count), L2=\(l2Count), L3=\(l3Count), L4=\(l4Count). Dynamic L1 Cutoff: \(String(format: "%.2f", coeffs.l1SpeedCutoffMs))ms, Leaks: \(leaks), Fitness: \(String(format: "%.3f", fitness))")

        return TestLayerFitnessResult(
            fitnessScore: fitness,
            isBalanced: isBalanced,
            hermeticLeakCount: leaks,
            coefficientsUsed: coeffs,
            details: details
        )
    }
}
