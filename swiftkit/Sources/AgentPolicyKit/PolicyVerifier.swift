import Foundation

public struct PolicyCounterexample: Sendable, Equatable {
    public let action: String
    public let resourceType: String
    public let conflictingForbidId: String
    public let conflictingPermitId: String
    public let explanation: String

    public init(
        action: String,
        resourceType: String,
        conflictingForbidId: String,
        conflictingPermitId: String,
        explanation: String
    ) {
        self.action = action
        self.resourceType = resourceType
        self.conflictingForbidId = conflictingForbidId
        self.conflictingPermitId = conflictingPermitId
        self.explanation = explanation
    }
}

public struct PolicyVerificationResult: Sendable, Equatable {
    public let hasDeadlock: Bool
    public let counterexamples: [PolicyCounterexample]
    public let shadowedPolicies: [String]

    public init(
        hasDeadlock: Bool,
        counterexamples: [PolicyCounterexample] = [],
        shadowedPolicies: [String] = []
    ) {
        self.hasDeadlock = hasDeadlock
        self.counterexamples = counterexamples
        self.shadowedPolicies = shadowedPolicies
    }
}

public struct PolicyVerifier: Sendable {
    public init() {}

    public func verify(
        policySet: PolicySet,
        knownActions: [String],
        knownResourceTypes: [String]
    ) -> PolicyVerificationResult {
        var counterexamples: [PolicyCounterexample] = []
        var shadowedPolicies: [String] = []

        let forbids = policySet.statements.filter { $0.effect == .forbid }
        let permits = policySet.statements.filter { $0.effect == .permit }

        for action in knownActions {
            for resType in knownResourceTypes {
                collectDeadlocks(
                    action: action,
                    resType: resType,
                    forbids: forbids,
                    permits: permits,
                    counterexamples: &counterexamples,
                    shadowedPolicies: &shadowedPolicies
                )
            }
        }

        return PolicyVerificationResult(
            hasDeadlock: !counterexamples.isEmpty,
            counterexamples: counterexamples,
            shadowedPolicies: shadowedPolicies
        )
    }

    private func collectDeadlocks(
        action: String,
        resType: String,
        forbids: [PolicyStatement],
        permits: [PolicyStatement],
        counterexamples: inout [PolicyCounterexample],
        shadowedPolicies: inout [String]
    ) {
        let syntheticResource = EntityIdentifier(type: resType, id: "synthetic-\(resType)")
        let syntheticPrincipal = EntityIdentifier.role("developer")

        let matchingForbids = forbids.filter { stmt in
            stmt.principal.matches(syntheticPrincipal) &&
            stmt.action.matches(action) &&
            stmt.resource.matches(syntheticResource) &&
            stmt.when.isEmpty &&
            stmt.unless.isEmpty
        }

        guard let unconditionalForbid = matchingForbids.first else { return }

        let matchingPermits = permits.filter { stmt in
            stmt.principal.matches(syntheticPrincipal) &&
            stmt.action.matches(action) &&
            stmt.resource.matches(syntheticResource)
        }

        for permit in matchingPermits {
            counterexamples.append(
                PolicyCounterexample(
                    action: action,
                    resourceType: resType,
                    conflictingForbidId: unconditionalForbid.id,
                    conflictingPermitId: permit.id,
                    explanation: "Unconditional forbid '\(unconditionalForbid.id)' completely shadows permit '\(permit.id)' for action '\(action)' on resource '\(resType)', causing permanent deadlock."
                )
            )
            if !shadowedPolicies.contains(permit.id) {
                shadowedPolicies.append(permit.id)
            }
        }
    }
}
