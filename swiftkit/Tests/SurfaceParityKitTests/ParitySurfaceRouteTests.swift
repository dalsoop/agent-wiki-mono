import XCTest
import SurfaceParityKit
#if canImport(SwiftUI)
import SwiftUI
#endif

private enum TestAppRoute: String, ParitySurfaceRoute {
    case dashboard
    case settings
    case analytics

    var surfaceLabel: String {
        switch self {
        case .dashboard: return "Dashboard Overview"
        case .settings: return "Preferences & Settings"
        case .analytics: return "Telemetry & Analytics"
        }
    }

    #if canImport(SwiftUI)
    @ViewBuilder
    var destinationView: some View {
        switch self {
        case .dashboard:
            Text("Dashboard Content")
        case .settings:
            Text("Settings Content")
        case .analytics:
            Text("Analytics Content")
        }
    }
    #endif

    func executeCLI() async throws {
        // Mock execution
        switch self {
        case .dashboard:
            break
        case .settings:
            break
        case .analytics:
            throw TestError.mockFailure
        }
    }
}

private enum TestError: Error {
    case mockFailure
}

final class ParitySurfaceRouteTests: XCTestCase {
    func testRouteIdentifiableAndAttributes() {
        XCTAssertEqual(TestAppRoute.dashboard.id, "dashboard")
        XCTAssertEqual(TestAppRoute.settings.id, "settings")
        XCTAssertEqual(TestAppRoute.dashboard.surfaceLabel, "Dashboard Overview")
        XCTAssertEqual(TestAppRoute.allCases.count, 3)
    }

    func testTypealiasEquivalence() {
        func acceptRoute<R: AppRouteProtocol>(_ route: R) -> String {
            route.id
        }
        XCTAssertEqual(acceptRoute(TestAppRoute.dashboard), "dashboard")
    }

    func testCLIAdapterResolution() async throws {
        let route = ParityRouteCLIAdapter<TestAppRoute>.resolveRoute(matching: "settings")
        XCTAssertEqual(route, .settings)

        let labelRoute = ParityRouteCLIAdapter<TestAppRoute>.resolveRoute(matching: "dashboard overview")
        XCTAssertEqual(labelRoute, .dashboard)

        let missing = ParityRouteCLIAdapter<TestAppRoute>.resolveRoute(matching: "nonexistent")
        XCTAssertNil(missing)

        // Successful dispatch
        try await ParityRouteCLIAdapter<TestAppRoute>.dispatch(identifier: "dashboard")

        // Throwing dispatch on known route
        do {
            try await ParityRouteCLIAdapter<TestAppRoute>.dispatch(identifier: "analytics")
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is TestError)
        }

        // Unknown route dispatch
        do {
            try await ParityRouteCLIAdapter<TestAppRoute>.dispatch(identifier: "invalid")
            XCTFail("Should have thrown unknown route")
        } catch let ParityRouteError.unknownRoute(identifier, available) {
            XCTAssertEqual(identifier, "invalid")
            XCTAssertEqual(available, ["dashboard", "settings", "analytics"])
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func testDestinationView() {
        let view = TestAppRoute.dashboard.destinationView
        XCTAssertNotNil(view)
    }
    #endif
}
