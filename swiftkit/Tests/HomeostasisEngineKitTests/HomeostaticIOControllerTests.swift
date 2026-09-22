import XCTest
@testable import HomeostasisEngineKit

final class HomeostaticIOControllerTests: XCTestCase {
    func testUnobservedDomainDoesNotInventIsolate() {
        let controller = HomeostaticIOController()
        XCTAssertEqual(controller.evaluatePreExecution(domain: "scan"), .steady)
        XCTAssertNil(controller.metric(for: "scan"))
    }

    func testFirstObservationIsIdentityAgainstSelf() throws {
        let controller = HomeostaticIOController()
        let observed: TimeInterval = 0.002
        let decision = controller.recordOperation(domain: "scan", duration: observed)

        XCTAssertTrue(decision.isHealthy)
        XCTAssertEqual(decision.action, .steady)
        XCTAssertEqual(decision.burnRate, 0, accuracy: 1e-12)

        let metric = try XCTUnwrap(controller.metric(for: "scan"))
        XCTAssertEqual(metric.totalOperations, 1)
        XCTAssertEqual(metric.slowOperations, 0)
        XCTAssertEqual(metric.meanDuration, observed, accuracy: 1e-12)
        XCTAssertFalse(metric.isIsolated)
    }

    func testLaterObservationComparesToPriorSelfNotFixedSLA() throws {
        let controller = HomeostaticIOController()
        _ = controller.recordOperation(domain: "scan", duration: 0.002)
        let slower = controller.recordOperation(domain: "scan", duration: 0.008)

        let metric = try XCTUnwrap(controller.metric(for: "scan"))
        XCTAssertEqual(metric.totalOperations, 2)
        XCTAssertEqual(metric.slowOperations, 1)
        XCTAssertGreaterThan(slower.burnRate, 0)
        XCTAssertNotEqual(metric.meanDuration, 0.050, accuracy: 1e-9)
    }
}
