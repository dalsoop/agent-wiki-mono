import Foundation

public enum GovernancePresets {
    public static func standardFleetPolicy() -> PolicySet {
        var set = PolicySet()
        for statement in foundationSCPStatements() {
            set.add(statement)
        }
        for statement in operationalGovernanceStatements() {
            set.add(statement)
        }
        return set
    }

    private static func foundationSCPStatements() -> [PolicyStatement] {
        [
            PolicyStatement(
                id: "scp-no-new-shell-scripts",
                effect: .forbid,
                principal: .any,
                action: .exact("commit"),
                resource: .ofType("ShellScript"),
                statementDescription: "Foundation SCP: Never permit committing raw shell scripts"
            ),
            PolicyStatement(
                id: "scp-no-secret-leakage",
                effect: .forbid,
                principal: .any,
                action: .exact("commit"),
                resource: .any,
                when: [.contextBoolEquals(key: "containsHardcodedSecret", value: true)],
                statementDescription: "Foundation SCP: Block commits containing hardcoded secrets"
            )
        ]
    }

    private static func operationalGovernanceStatements() -> [PolicyStatement] {
        [
            PolicyStatement(
                id: "permit-daemon-surface-exemption",
                effect: .permit,
                principal: .any,
                action: .exact("gate:surface_parity"),
                resource: .ofType("App"),
                when: [
                    .or([
                        .attributeEquals(key: "profile", value: "daemon"),
                        .attributeEquals(key: "profile", value: "cli-only")
                    ])
                ],
                statementDescription: "ABAC Exemption: Daemon and CLI apps are exempt from GUI StateMirror parity"
            ),
            PolicyStatement(
                id: "permit-gui-surface-check",
                effect: .permit,
                principal: .any,
                action: .exact("gate:surface_parity"),
                resource: .ofType("App"),
                when: [
                    .attributeEquals(key: "profile", value: "gui-app"),
                    .contextBoolEquals(key: "isHeadlessCI", value: false)
                ],
                statementDescription: "Enforce surface parity on GUI apps when not running in headless CI"
            ),
            PolicyStatement(
                id: "permit-baseline-grandfathered-debt",
                effect: .permit,
                principal: .any,
                action: .exact("gate:lint"),
                resource: .ofType("App"),
                when: [.contextBoolEquals(key: "isNewDiffViolation", value: false)],
                statementDescription: "Baseline Ratchet: Permit legacy grandfathered debt"
            ),
            PolicyStatement(
                id: "forbid-new-diff-lint-violations",
                effect: .forbid,
                principal: .any,
                action: .exact("gate:lint"),
                resource: .ofType("App"),
                when: [.contextBoolEquals(key: "isNewDiffViolation", value: true)],
                statementDescription: "Baseline Ratchet: Forbid new diff lint violations"
            ),
            PolicyStatement(
                id: "permit-app-ship",
                effect: .permit,
                principal: .any,
                action: .exact("ship"),
                resource: .ofType("App"),
                unless: [.contextBoolEquals(key: "hasCompileError", value: true)],
                statementDescription: "General permit to ship app if no compile errors"
            )
        ]
    }
}
