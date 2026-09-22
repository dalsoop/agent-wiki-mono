import Foundation

public struct AuthorizationRequest: Sendable, Equatable {
    public let principal: EntityIdentifier
    public let action: String
    public let resource: EntityIdentifier
    public let resourceAttributes: [String: String]
    public let context: [String: String]

    public init(
        principal: EntityIdentifier,
        action: String,
        resource: EntityIdentifier,
        resourceAttributes: [String: String] = [:],
        context: [String: String] = [:]
    ) {
        self.principal = principal
        self.action = action
        self.resource = resource
        self.resourceAttributes = resourceAttributes
        self.context = context
    }
}

public struct AuthorizationDecision: Sendable, Equatable {
    public let isAllowed: Bool
    public let determiningPolicies: [String]
    public let reason: String
    public let evaluationDurationMicroseconds: Double

    public init(
        isAllowed: Bool,
        determiningPolicies: [String],
        reason: String,
        evaluationDurationMicroseconds: Double = 0.0
    ) {
        self.isAllowed = isAllowed
        self.determiningPolicies = determiningPolicies
        self.reason = reason
        self.evaluationDurationMicroseconds = evaluationDurationMicroseconds
    }
}

public final class PolicyAuthorizer: Sendable {
    private let policySet: PolicySet
    private let actionIndex: [String: [PolicyStatement]]
    private let wildcardPolicies: [PolicyStatement]

    public init(policySet: PolicySet) {
        self.policySet = policySet
        var index: [String: [PolicyStatement]] = [:]
        var wildcards: [PolicyStatement] = []

        for statement in policySet.statements {
            switch statement.action {
            case .any:
                wildcards.append(statement)
            case .exact(let act):
                index[act, default: []].append(statement)
            case .inList(let list):
                for act in list {
                    index[act, default: []].append(statement)
                }
            }
        }

        self.actionIndex = index
        self.wildcardPolicies = wildcards
    }

    public func authorize(_ request: AuthorizationRequest) -> AuthorizationDecision {
        let startTime = DispatchTime.now().uptimeNanoseconds

        let candidates = (actionIndex[request.action] ?? []) + wildcardPolicies

        var permitMatches: [String] = []
        var forbidMatches: [String] = []

        for statement in candidates {
            guard statement.applies(
                principal: request.principal,
                action: request.action,
                resource: request.resource,
                resourceAttributes: request.resourceAttributes,
                context: request.context
            ) else {
                continue
            }

            switch statement.effect {
            case .forbid:
                forbidMatches.append(statement.id)
            case .permit:
                permitMatches.append(statement.id)
            }
        }

        let endTime = DispatchTime.now().uptimeNanoseconds
        let elapsedMicros = Double(endTime - startTime) / 1000.0

        if !forbidMatches.isEmpty {
            return AuthorizationDecision(
                isAllowed: false,
                determiningPolicies: forbidMatches,
                reason: "Explicit forbid override: \(forbidMatches.joined(separator: ", "))",
                evaluationDurationMicroseconds: elapsedMicros
            )
        }

        if !permitMatches.isEmpty {
            return AuthorizationDecision(
                isAllowed: true,
                determiningPolicies: permitMatches,
                reason: "Explicit permit matched: \(permitMatches.joined(separator: ", "))",
                evaluationDurationMicroseconds: elapsedMicros
            )
        }

        return AuthorizationDecision(
            isAllowed: false,
            determiningPolicies: [],
            reason: "Default deny: no matching permit policy",
            evaluationDurationMicroseconds: elapsedMicros
        )
    }
}
