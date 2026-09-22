import XCTest
@testable import AgentPolicyKit

final class CedarPolicyEngineTests: XCTestCase {
    func testMicrosecondEvaluationSpeed() {
        let policySet = GovernancePresets.standardFleetPolicy()
        let authorizer = PolicyAuthorizer(policySet: policySet)

        let request = AuthorizationRequest(
            principal: EntityIdentifier.role("agent"),
            action: "gate:surface_parity",
            resource: EntityIdentifier.app("detailpage-template-studio"),
            resourceAttributes: ["profile": "daemon"],
            context: [:]
        )

        let decision = authorizer.authorize(request)
        XCTAssertTrue(decision.isAllowed)
        XCTAssertLessThan(decision.evaluationDurationMicroseconds, 1000.0)
    }

    func testExplicitForbidOverridesPermit() {
        var set = PolicySet()
        set.add(
            PolicyStatement(
                id: "permit-ship",
                effect: .permit,
                principal: .any,
                action: .exact("ship"),
                resource: .ofType("App")
            )
        )
        set.add(
            PolicyStatement(
                id: "forbid-ship-when-broken",
                effect: .forbid,
                principal: .any,
                action: .exact("ship"),
                resource: .ofType("App"),
                when: [.contextBoolEquals(key: "isBroken", value: true)]
            )
        )

        let authorizer = PolicyAuthorizer(policySet: set)

        let normalReq = AuthorizationRequest(
            principal: .role("dev"),
            action: "ship",
            resource: .app("app-a"),
            context: ["isBroken": "false"]
        )
        XCTAssertTrue(authorizer.authorize(normalReq).isAllowed)

        let brokenReq = AuthorizationRequest(
            principal: .role("dev"),
            action: "ship",
            resource: .app("app-a"),
            context: ["isBroken": "true"]
        )
        let brokenDecision = authorizer.authorize(brokenReq)
        XCTAssertFalse(brokenDecision.isAllowed)
        XCTAssertTrue(brokenDecision.determiningPolicies.contains("forbid-ship-when-broken"))
    }

    func testDefaultDeny() {
        let emptyAuthorizer = PolicyAuthorizer(policySet: PolicySet())
        let req = AuthorizationRequest(
            principal: .role("dev"),
            action: "deploy",
            resource: .app("any-app")
        )
        let decision = emptyAuthorizer.authorize(req)
        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, "Default deny: no matching permit policy")
    }

    func testABACDaemonProfileExemption() {
        let authorizer = PolicyAuthorizer(policySet: GovernancePresets.standardFleetPolicy())

        let daemonReq = AuthorizationRequest(
            principal: .role("agent"),
            action: "gate:surface_parity",
            resource: .app("daemon-sync"),
            resourceAttributes: ["profile": "daemon"]
        )
        XCTAssertTrue(authorizer.authorize(daemonReq).isAllowed)

        let cliReq = AuthorizationRequest(
            principal: .role("agent"),
            action: "gate:surface_parity",
            resource: .app("cmd-tool"),
            resourceAttributes: ["profile": "cli-only"]
        )
        XCTAssertTrue(authorizer.authorize(cliReq).isAllowed)

        let unprofiledReq = AuthorizationRequest(
            principal: .role("agent"),
            action: "gate:surface_parity",
            resource: .app("unknown-app"),
            resourceAttributes: [:]
        )
        XCTAssertFalse(authorizer.authorize(unprofiledReq).isAllowed)
    }

    func testBaselineRatchet() {
        let authorizer = PolicyAuthorizer(policySet: GovernancePresets.standardFleetPolicy())

        let grandfatheredReq = AuthorizationRequest(
            principal: .role("dev"),
            action: "gate:lint",
            resource: .app("legacy-app"),
            context: ["isNewDiffViolation": "false"]
        )
        XCTAssertTrue(authorizer.authorize(grandfatheredReq).isAllowed)

        let newViolationReq = AuthorizationRequest(
            principal: .role("dev"),
            action: "gate:lint",
            resource: .app("new-app"),
            context: ["isNewDiffViolation": "true"]
        )
        let decision = authorizer.authorize(newViolationReq)
        XCTAssertFalse(decision.isAllowed)
        XCTAssertTrue(decision.determiningPolicies.contains("forbid-new-diff-lint-violations"))
    }

    func testDeadlockVerificationAndCounterexample() {
        var set = PolicySet()
        set.add(
            PolicyStatement(
                id: "permit-ship",
                effect: .permit,
                principal: .any,
                action: .exact("ship"),
                resource: .ofType("App")
            )
        )
        set.add(
            PolicyStatement(
                id: "unconditional-forbid-ship",
                effect: .forbid,
                principal: .any,
                action: .exact("ship"),
                resource: .ofType("App")
            )
        )

        let verifier = PolicyVerifier()
        let result = verifier.verify(
            policySet: set,
            knownActions: ["ship", "lint"],
            knownResourceTypes: ["App"]
        )

        XCTAssertTrue(result.hasDeadlock)
        XCTAssertEqual(result.counterexamples.count, 1)
        XCTAssertEqual(result.counterexamples.first?.conflictingForbidId, "unconditional-forbid-ship")
        XCTAssertEqual(result.counterexamples.first?.conflictingPermitId, "permit-ship")
        XCTAssertTrue(result.shadowedPolicies.contains("permit-ship"))
    }
}
