import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// An abstraction for surfaces/routes across GUI and CLI within mono apps.
/// Provides a unified contract ensuring that each route has a corresponding
/// surface label, UI view destination, and CLI execution entry point.
public protocol ParitySurfaceRoute: CaseIterable, Hashable, Identifiable, Sendable where ID == String {
    #if canImport(SwiftUI)
    associatedtype DestinationView: View
    @MainActor @ViewBuilder var destinationView: DestinationView { get }
    #endif

    /// The human-readable label or title of the surface/route.
    var surfaceLabel: String { get }

    /// Asynchronously executes the CLI command or operation corresponding to this route.
    func executeCLI() async throws
}

/// Convenience default implementations for `ParitySurfaceRoute`.
extension ParitySurfaceRoute {
    /// By default, if the type is also `RawRepresentable` with `RawValue == String`,
    /// `id` will match `rawValue`.
    public var id: String {
        if let raw = (self as? any RawRepresentable)?.rawValue as? String {
            return raw
        }
        return String(describing: self)
    }
}

/// Typealias for backward compatibility or alternative naming.
public typealias AppRouteProtocol = ParitySurfaceRoute
