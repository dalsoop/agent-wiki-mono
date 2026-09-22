import XCTest
import AppContractTestKit

enum SampleAppIntent: String, ActionIntent {
    case inspect
    case update
    case reset
}

struct CompleteSampleContract: DeclarativeAppContract {
    typealias Intent = SampleAppIntent

    var appSlug: String { "sample-app" }
    var supportedIntents: [SampleAppIntent] { SampleAppIntent.allCases }
}

struct DeficientSampleContract: DeclarativeAppContract {
    typealias Intent = SampleAppIntent

    var appSlug: String { "deficient-app" }
    var supportedIntents: [SampleAppIntent] { [.inspect, .update] }

    func coverage(for intent: SampleAppIntent) -> SurfaceCoverage {
        switch intent {
        case .inspect:
            return .full
        case .update:
            return SurfaceCoverage(supportedSurfaces: [.cli, .core])
        case .reset:
            return .none
        }
    }
}

final class DeclarativeAppContractTests: XCTestCase {
    func testCompleteContractValidation() {
        let contract = CompleteSampleContract()
        let report = contract.validateContract()

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.totalIntents, 3)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertTrue(report.surfaceGaps.isEmpty)
    }

    func testDeficientContractValidationDetectsGaps() {
        let contract = DeficientSampleContract()
        let report = contract.validateContract()

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.surfaceGaps[.update], Set([.gui, .stateMirror]))
        XCTAssertEqual(report.violations.count, 2)
    }

    func testAnyDeclarativeAppContract() {
        let contract = AnyDeclarativeAppContract(
            appSlug: "dynamic-app",
            supportedIntents: [SampleAppIntent.reset]
        )

        let report = contract.validateContract()
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.appSlug, "dynamic-app")
        XCTAssertEqual(contract.executableName, "dynamic-app")
        XCTAssertEqual(contract.bundleIdentifier, "net.ranode.dynamic-app")
    }
}
