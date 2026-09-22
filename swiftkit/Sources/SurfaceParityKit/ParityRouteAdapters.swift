import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI navigation helper views for `ParitySurfaceRoute`.
@available(macOS 11.0, iOS 14.0, *)
public struct ParityRoutePicker<Route: ParitySurfaceRoute>: View {
    @Binding public var selection: Route

    public init(selection: Binding<Route>) {
        self._selection = selection
    }

    public var body: some View {
        Picker("Route", selection: $selection) {
            ForEach(Array(Route.allCases), id: \.id) { route in
                Text(route.surfaceLabel).tag(route)
            }
        }
    }
}

@available(macOS 11.0, iOS 14.0, *)
public struct ParityRouteSidebar<Route: ParitySurfaceRoute>: View {
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
#endif

/// A registry or adapter that facilitates routing commands from CLI string inputs (e.g. from ArgumentParser or ProcessInfo)
/// to the corresponding `ParitySurfaceRoute`.
public struct ParityRouteCLIAdapter<Route: ParitySurfaceRoute> {
    public init() {}

    /// Finds a route matching the given identifier or string name.
    public static func resolveRoute(matching identifier: String) -> Route? {
        let canonicalIdentifier = RouteParityGate.canonicalToken(identifier)
        return Route.allCases.first { route in
            route.id.caseInsensitiveCompare(identifier) == .orderedSame ||
            route.surfaceLabel.caseInsensitiveCompare(identifier) == .orderedSame ||
            RouteParityGate.canonicalToken(route.id) == canonicalIdentifier ||
            RouteParityGate.canonicalToken(route.surfaceLabel) == canonicalIdentifier
        }
    }

    /// Resolves the route by string identifier and executes its CLI operation.
    public static func dispatch(identifier: String) async throws {
        guard let route = resolveRoute(matching: identifier) else {
            throw ParityRouteError.unknownRoute(identifier: identifier, available: Route.allCases.map(\.id))
        }
        try await route.executeCLI()
    }
}

public enum ParityRouteError: Error, LocalizedError, Equatable, Sendable {
    case unknownRoute(identifier: String, available: [String])
    case notImplemented(route: String)

    public var errorDescription: String? {
        switch self {
        case .unknownRoute(let identifier, let available):
            return "Unknown route '\(identifier)'. Available routes: \(available.joined(separator: ", "))"
        case .notImplemented(let route):
            return "Route '\(route)' CLI command is not yet implemented"
        }
    }
}
