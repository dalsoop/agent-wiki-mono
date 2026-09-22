import Foundation

/// Key paths are immutable runtime metadata but are not yet declared Sendable
/// by the standard library. Keep the unchecked boundary narrower than the
/// cleanup closure so arbitrary captures still receive compiler checking.
private struct SendableWritableKeyPath<Root, Value>: @unchecked Sendable {
    let value: WritableKeyPath<Root, Value>
}

public protocol GameSimulationComponent: Codable, Equatable, Sendable {
    static var componentID: String { get }
    var entityID: GameEntityID { get }
    init(entityID: GameEntityID)
}

public enum GameComponentRegistryError: Error, Equatable, Sendable {
    case emptyComponentID
    case duplicateComponentID(String)

    public var code: String {
        switch self {
        case .emptyComponentID: "component.empty-id"
        case .duplicateComponentID: "component.duplicate-id"
        }
    }
}

public struct GameComponentRegistration<State: Sendable>: Sendable {
    public let componentID: String
    private let cleanup: @Sendable (GameEntityID, inout State) -> Void

    public init<Component: GameSimulationComponent>(
        _ type: Component.Type,
        at keyPath: WritableKeyPath<State, [GameEntityID: Component]>
    ) {
        componentID = Component.componentID
        let sendableKeyPath = SendableWritableKeyPath(value: keyPath)
        cleanup = { entityID, state in
            state[keyPath: sendableKeyPath.value][entityID] = nil
        }
    }

    public init(
        componentID: String,
        cleanup: @escaping @Sendable (GameEntityID, inout State) -> Void
    ) {
        self.componentID = componentID
        self.cleanup = cleanup
    }

    public func remove(from state: inout State, entityID: GameEntityID) {
        cleanup(entityID, &state)
    }
}

public struct GameComponentRegistry<State: Sendable>: Sendable {
    private var registrations: [String: GameComponentRegistration<State>]

    public init() {
        registrations = [:]
    }

    public var componentIDs: [String] {
        registrations.keys.sorted()
    }

    public mutating func register(
        _ registration: GameComponentRegistration<State>
    ) throws {
        guard !registration.componentID.isEmpty else {
            throw GameComponentRegistryError.emptyComponentID
        }
        guard registrations[registration.componentID] == nil else {
            throw GameComponentRegistryError.duplicateComponentID(registration.componentID)
        }
        registrations[registration.componentID] = registration
    }

    public func removeAll(for entityID: GameEntityID, from state: inout State) {
        for componentID in componentIDs {
            registrations[componentID]?.remove(from: &state, entityID: entityID)
        }
    }
}
