import Foundation

public enum PolicyEffect: String, Codable, Sendable, Equatable {
    case permit
    case forbid
}

public struct EntityIdentifier: Codable, Sendable, Equatable, Hashable {
    public let type: String
    public let id: String

    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }

    public static func app(_ id: String) -> EntityIdentifier {
        EntityIdentifier(type: "App", id: id)
    }

    public static func role(_ id: String) -> EntityIdentifier {
        EntityIdentifier(type: "Role", id: id)
    }

    public static func resource(_ type: String, id: String) -> EntityIdentifier {
        EntityIdentifier(type: type, id: id)
    }
}

public enum PrincipalPattern: Codable, Sendable, Equatable {
    case any
    case exact(EntityIdentifier)
    case inGroup(EntityIdentifier)

    public func matches(_ entity: EntityIdentifier) -> Bool {
        switch self {
        case .any:
            return true
        case .exact(let target):
            return target == entity
        case .inGroup(let group):
            return entity.type == group.type
        }
    }
}

public enum ActionPattern: Codable, Sendable, Equatable {
    case any
    case exact(String)
    case inList([String])

    public func matches(_ action: String) -> Bool {
        switch self {
        case .any:
            return true
        case .exact(let target):
            return target == action
        case .inList(let list):
            return list.contains(action)
        }
    }
}

public enum ResourcePattern: Codable, Sendable, Equatable {
    case any
    case exact(EntityIdentifier)
    case ofType(String)

    public func matches(_ entity: EntityIdentifier) -> Bool {
        switch self {
        case .any:
            return true
        case .exact(let target):
            return target == entity
        case .ofType(let type):
            return entity.type == type
        }
    }
}

public indirect enum PolicyCondition: Codable, Sendable, Equatable {
    case attributeEquals(key: String, value: String)
    case attributeNotEquals(key: String, value: String)
    case hasAttribute(key: String)
    case contextStringEquals(key: String, value: String)
    case contextBoolEquals(key: String, value: Bool)
    case and([PolicyCondition])
    case or([PolicyCondition])
    case not(PolicyCondition)

    public func evaluate(resourceAttributes: [String: String], context: [String: String]) -> Bool {
        switch self {
        case .attributeEquals(let key, let value):
            return resourceAttributes[key] == value
        case .attributeNotEquals(let key, let value):
            return resourceAttributes[key] != value
        case .hasAttribute(let key):
            return resourceAttributes[key] != nil
        case .contextStringEquals(let key, let value):
            return context[key] == value
        case .contextBoolEquals(let key, let value):
            return (context[key]?.lowercased() == "true") == value
        case .and(let conditions):
            return conditions.allSatisfy { $0.evaluate(resourceAttributes: resourceAttributes, context: context) }
        case .or(let conditions):
            return conditions.contains { $0.evaluate(resourceAttributes: resourceAttributes, context: context) }
        case .not(let condition):
            return !condition.evaluate(resourceAttributes: resourceAttributes, context: context)
        }
    }
}

public struct PolicyStatement: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let effect: PolicyEffect
    public let principal: PrincipalPattern
    public let action: ActionPattern
    public let resource: ResourcePattern
    public let when: [PolicyCondition]
    public let unless: [PolicyCondition]
    public let statementDescription: String

    public init(
        id: String,
        effect: PolicyEffect,
        principal: PrincipalPattern = .any,
        action: ActionPattern = .any,
        resource: ResourcePattern = .any,
        when: [PolicyCondition] = [],
        unless: [PolicyCondition] = [],
        statementDescription: String = ""
    ) {
        self.id = id
        self.effect = effect
        self.principal = principal
        self.action = action
        self.resource = resource
        self.when = when
        self.unless = unless
        self.statementDescription = statementDescription
    }

    public func applies(
        principal: EntityIdentifier,
        action: String,
        resource: EntityIdentifier,
        resourceAttributes: [String: String],
        context: [String: String]
    ) -> Bool {
        guard self.principal.matches(principal) else { return false }
        guard self.action.matches(action) else { return false }
        guard self.resource.matches(resource) else { return false }

        let whenSatisfied = when.isEmpty || when.allSatisfy { $0.evaluate(resourceAttributes: resourceAttributes, context: context) }
        guard whenSatisfied else { return false }

        let unlessSatisfied = unless.contains { $0.evaluate(resourceAttributes: resourceAttributes, context: context) }
        guard !unlessSatisfied else { return false }

        return true
    }
}

public struct PolicySet: Codable, Sendable, Equatable {
    public var statements: [PolicyStatement]

    public init(statements: [PolicyStatement] = []) {
        self.statements = statements
    }

    public mutating func add(_ statement: PolicyStatement) {
        statements.removeAll { $0.id == statement.id }
        statements.append(statement)
    }

    public func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
