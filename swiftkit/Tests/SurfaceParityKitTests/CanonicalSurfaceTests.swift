import XCTest
import SurfaceParityKit
#if canImport(SwiftUI)
import SwiftUI
#endif

private struct MockAppState: CanonicalSurfaceState {
    var status: String
    var lastError: String?
    var updatedAt: Date
    var count: Int
}

private final class MockEngine: SurfaceCoreEngine {
    typealias State = MockAppState

    @Published var state: MockAppState
    let appSlug: String

    init(appSlug: String, initialState: MockAppState) {
        self.appSlug = appSlug
        self.state = initialState
    }
}

private enum MockAppRoute: String, CanonicalSurfaceRoute {
    case home
    case status
    case bump

    var surfaceLabel: String {
        switch self {
        case .home: return "Home View"
        case .status: return "Status View"
        case .bump: return "Increment Count"
        }
    }

    var cliCommandName: String {
        switch self {
        case .home: return "home"
        case .status: return "status"
        case .bump: return "bump"
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    @ViewBuilder
    func destinationView(engine: MockEngine) -> some View {
        switch self {
        case .home:
            Text("Status: \(engine.state.status)")
        case .status:
            Text("Updated: \(engine.state.updatedAt)")
        case .bump:
            Text("Count: \(engine.state.count)")
        }
    }
    #endif

    func executeCLI(engine: MockEngine, arguments: [String]) async throws {
        switch self {
        case .home, .status:
            break
        case .bump:
            engine.mutate { state in
                state.count += 1
                state.status = "bumped"
            }
        }
    }
}

#if canImport(SwiftUI)
@available(macOS 11.0, iOS 14.0, *)
private struct MockCanonicalApp: CanonicalSurfaceApp {
    typealias Route = MockAppRoute
    typealias Engine = MockEngine

    @StateObject var engine: MockEngine

    init() {
        _engine = StateObject(wrappedValue: MockEngine(
            appSlug: "MockApp",
            initialState: MockAppState(status: "idle", lastError: nil, updatedAt: Date(), count: 0)
        ))
    }

    var body: some Scene {
        WindowGroup {
            CanonicalSurfaceHostView(engine: engine, currentRoute: .constant(MockAppRoute.home))
        }
    }
}
#endif

@MainActor
final class CanonicalSurfaceTests: XCTestCase {
    func testStateAndEngineMutation() async throws {
        let initialDate = Date()
        let engine = MockEngine(
            appSlug: "MockEngineApp",
            initialState: MockAppState(status: "ready", lastError: nil, updatedAt: initialDate, count: 10)
        )

        XCTAssertEqual(engine.state.status, "ready")
        XCTAssertEqual(engine.state.count, 10)

        engine.mutate { state in
            state.status = "running"
            state.count = 20
        }

        XCTAssertEqual(engine.state.status, "running")
        XCTAssertEqual(engine.state.count, 20)
    }

    func testCanonicalRouteCLIAdapterDispatch() async throws {
        let engine = MockEngine(
            appSlug: "MockEngineApp",
            initialState: MockAppState(status: "ready", lastError: nil, updatedAt: Date(), count: 10)
        )

        let adapter = CanonicalRouteCLIAdapter<MockAppRoute, MockEngine>(engine: engine)

        try await adapter.dispatch(command: "bump")
        XCTAssertEqual(engine.state.count, 11)
        XCTAssertEqual(engine.state.status, "bumped")

        // Test resolution by surface label
        let resolvedByLabel = CanonicalRouteCLIAdapter<MockAppRoute, MockEngine>.resolveRoute(matching: "Increment Count")
        XCTAssertEqual(resolvedByLabel, .bump)

        // Test unknown command
        do {
            try await adapter.dispatch(command: "invalid-command")
            XCTFail("Should throw unknownRoute")
        } catch let ParityRouteError.unknownRoute(identifier, available) {
            XCTAssertEqual(identifier, "invalid-command")
            XCTAssertTrue(available.contains("bump"))
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func testCanonicalHostViewDestination() {
        let engine = MockEngine(
            appSlug: "MockEngineApp",
            initialState: MockAppState(status: "ready", lastError: nil, updatedAt: Date(), count: 42)
        )
        let view = MockAppRoute.home.destinationView(engine: engine)
        XCTAssertNotNil(view)
    }
    #endif
}
