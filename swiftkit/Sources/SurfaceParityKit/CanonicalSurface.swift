import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
import Combine
import StateMirrorKit

// MARK: - CanonicalSurfaceState

/// Canonical state protocol representing a surface state that can be mirrored and observed.
public protocol CanonicalSurfaceState: Codable, Sendable, Equatable {
    var status: String { get }
    var lastError: String? { get }
    var updatedAt: Date { get }
}

// MARK: - SurfaceCoreEngine

/// Core engine managing state mutations, persistence, and state mirroring.
@MainActor
public protocol SurfaceCoreEngine: AnyObject, ObservableObject {
    associatedtype State: CanonicalSurfaceState

    var state: State { get set }
    var appSlug: String { get }

    func reloadFromMirror() async throws
    func mutate(_ transform: (inout State) throws -> Void) rethrows
}

extension SurfaceCoreEngine {
    /// Default mutation implementation updating state and publishing to StateMirror and StateMirrorSignal.
    public func mutate(_ transform: (inout State) throws -> Void) rethrows {
        try transform(&state)
        StateMirror.publish(app: appSlug, state)
        StateMirrorSignal.post(app: appSlug)
    }

    /// Reloads current state from StateMirror envelope if available.
    @MainActor
    public func reloadFromMirror() async throws {
        let slug = appSlug
        let envelope = try StateMirror.read(app: slug, as: State.self)
        self.state = envelope.state
    }
}

// MARK: - CanonicalSurfaceRoute

/// Surface route contract unifying GUI surface view, label, and CLI command execution with an engine.
public protocol CanonicalSurfaceRoute: CaseIterable, Hashable, Identifiable, Sendable where ID == String {
    associatedtype Engine: SurfaceCoreEngine
    #if canImport(SwiftUI)
    associatedtype DestinationView: View
    @MainActor @ViewBuilder func destinationView(engine: Engine) -> DestinationView
    #endif

    var surfaceLabel: String { get }
    var cliCommandName: String { get }

    @MainActor
    func executeCLI(engine: Engine, arguments: [String]) async throws
}

extension CanonicalSurfaceRoute {
    public var id: String {
        if let raw = (self as? any RawRepresentable)?.rawValue as? String {
            return raw
        }
        return String(describing: self)
    }

    public var cliCommandName: String {
        id
    }
}

// MARK: - SwiftUI Adapters & CanonicalSurfaceApp

#if canImport(SwiftUI)
/// A standard SwiftUI container view binding a `CanonicalSurfaceRoute` and `SurfaceCoreEngine`.
@available(macOS 11.0, iOS 14.0, *)
public struct CanonicalSurfaceHostView<Route: CanonicalSurfaceRoute, Engine: SurfaceCoreEngine>: View where Route.Engine == Engine {
    @ObservedObject public var engine: Engine
    @Binding public var currentRoute: Route

    public init(engine: Engine, currentRoute: Binding<Route>) {
        self.engine = engine
        self._currentRoute = currentRoute
    }

    public var body: some View {
        currentRoute.destinationView(engine: engine)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name(StateMirrorSignal.notificationName(for: engine.appSlug)))) { _ in
                Task { @MainActor in
                    try? await engine.reloadFromMirror()
                }
            }
    }
}

/// A dedicated menu bar popover host view that embeds a route's view and auto-refreshes on StateMirror signals.
@available(macOS 11.0, iOS 14.0, *)
public struct CanonicalMenuBarHostView<Route: CanonicalSurfaceRoute, Engine: SurfaceCoreEngine>: View where Route.Engine == Engine {
    @ObservedObject public var engine: Engine
    public let defaultRoute: Route

    public init(engine: Engine, defaultRoute: Route) {
        self.engine = engine
        self.defaultRoute = defaultRoute
    }

    public var body: some View {
        defaultRoute.destinationView(engine: engine)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name(StateMirrorSignal.notificationName(for: engine.appSlug)))) { _ in
                Task { @MainActor in
                    try? await engine.reloadFromMirror()
                }
            }
    }
}

/// Navigation sidebar picker for `CanonicalSurfaceRoute`.
@available(macOS 11.0, iOS 14.0, *)
public struct CanonicalRouteSidebar<Route: CanonicalSurfaceRoute>: View {
    @Binding public var selection: Route?

    public init(selection: Binding<Route?>) {
        self._selection = selection
    }

    public var body: some View {
        List(Array(Route.allCases), id: \.id, selection: $selection) { route in
            Text(route.surfaceLabel)
                .tag(Optional(route))
        }
    }
}

/// Top-level app protocol unifying Core Engine, Routes, and SwiftUI App presentation.
@available(macOS 11.0, iOS 14.0, *)
public protocol CanonicalSurfaceApp: App {
    associatedtype Route: CanonicalSurfaceRoute
    associatedtype Engine: SurfaceCoreEngine where Route.Engine == Engine

    var engine: Engine { get }
}
#endif

// MARK: - CanonicalRouteCLIAdapter

/// CLI command router resolving and executing CLI commands for a `CanonicalSurfaceRoute`.
public struct CanonicalRouteCLIAdapter<Route: CanonicalSurfaceRoute, Engine: SurfaceCoreEngine> where Route.Engine == Engine {
    public let engine: Engine

    public init(engine: Engine) {
        self.engine = engine
    }

    /// Resolves route matching given token or command name.
    public static func resolveRoute(matching identifier: String) -> Route? {
        let canonicalIdentifier = RouteParityGate.canonicalToken(identifier)
        return Route.allCases.first { route in
            route.id.caseInsensitiveCompare(identifier) == .orderedSame ||
            route.cliCommandName.caseInsensitiveCompare(identifier) == .orderedSame ||
            route.surfaceLabel.caseInsensitiveCompare(identifier) == .orderedSame ||
            RouteParityGate.canonicalToken(route.id) == canonicalIdentifier ||
            RouteParityGate.canonicalToken(route.cliCommandName) == canonicalIdentifier ||
            RouteParityGate.canonicalToken(route.surfaceLabel) == canonicalIdentifier
        }
    }

    /// Dispatches command to resolved route.
    @MainActor
    public func dispatch(command: String, arguments: [String] = []) async throws {
        guard let route = Self.resolveRoute(matching: command) else {
            throw ParityRouteError.unknownRoute(
                identifier: command,
                available: Route.allCases.map(\.cliCommandName)
            )
        }
        try await route.executeCLI(engine: engine, arguments: arguments)
    }
}
