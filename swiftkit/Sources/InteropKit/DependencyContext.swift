import Foundation

/// Defines a dependency key for type-safe dependency injection.
///
/// Implement this protocol to define a new dependency with default `liveValue`
/// and `testValue` implementations.
public protocol DependencyKey: Sendable {
    associatedtype Value: Sendable
    static var liveValue: Value { get }
    static var testValue: Value { get }
}

public extension DependencyKey {
    static var testValue: Value {
        liveValue
    }
}

/// A container of dependency values propagated via Swift Concurrency TaskLocal.
///
/// Zero-static DI container with value semantics, supporting scope isolation
/// without global mutable state.
public struct DependencyValues: Sendable {
    @TaskLocal public static var current = DependencyValues()

    private var storage: [ObjectIdentifier: any Sendable] = [:]
    public var isTestContext: Bool

    public init(isTestContext: Bool? = nil) {
        self.isTestContext = isTestContext ?? Self.detectTestContext()
    }

    private static func detectTestContext() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    public subscript<Key: DependencyKey>(key: Key.Type) -> Key.Value {
        get {
            if let value = storage[ObjectIdentifier(key)] as? Key.Value {
                return value
            }
            return isTestContext ? Key.testValue : Key.liveValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }

    public mutating func set<Key: DependencyKey>(_ key: Key.Type, to value: Key.Value) {
        self[key] = value
    }
}

/// Executes a synchronous operation with scoped dependency modifications.
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) throws -> Void,
    operation: () throws -> R
) rethrows -> R {
    var values = DependencyValues.current
    try mutate(&values)
    return try DependencyValues.$current.withValue(values) {
        try operation()
    }
}

/// Executes an asynchronous operation with scoped dependency modifications.
@discardableResult
public func withDependencies<R>(
    _ mutate: (inout DependencyValues) throws -> Void,
    operation: () async throws -> R
) async rethrows -> R {
    var values = DependencyValues.current
    try mutate(&values)
    return try await DependencyValues.$current.withValue(values) {
        try await operation()
    }
}

/// Property wrapper for injecting dependencies from the current `DependencyValues`.
@propertyWrapper
public struct Dependency<Value: Sendable>: Sendable {
    private let resolve: @Sendable () -> Value

    public init<Key: DependencyKey>(_ key: Key.Type) where Key.Value == Value {
        self.resolve = { DependencyValues.current[key] }
    }

    public init(_ keyPath: KeyPath<DependencyValues, Value> & Sendable) {
        self.resolve = { DependencyValues.current[keyPath: keyPath] }
    }

    public var wrappedValue: Value {
        resolve()
    }
}
