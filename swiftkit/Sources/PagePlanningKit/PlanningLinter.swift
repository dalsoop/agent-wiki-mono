import Foundation

public struct PlanningLintDefect: Sendable, CustomStringConvertible {
    public let ruleID: String
    public let message: String
    public let path: String

    public init(ruleID: String, message: String, path: String) {
        self.ruleID = ruleID
        self.message = message
        self.path = path
    }

    public var description: String {
        "[\(ruleID)] \(path): \(message)"
    }
}

/// Planning Linter enforcing Zero-CSS, PC 1440px SSOT, UUIDv4, and Semantic Primitives
public struct PlanningLinter: Sendable {
    public static let allowedPrimitives: Set<String> = [
        "HeroBlock", "FeatureCluster", "SelectorCluster", "ActionCluster",
        "NoticeBanner", "DataTable", "ThreadStream"
    ]

    public static let allowedArchetypes: Set<String> = [
        "catalog", "detail", "transaction", "form", "conversation"
    ]

    public init() {}

    public func lint(spec: PageSpec) -> [PlanningLintDefect] {
        var defects: [PlanningLintDefect] = []

        // 1. PC 1440px SSOT
        if spec.targetEnvironment != "PC-Desktop-1440" {
            defects.append(PlanningLintDefect(
                ruleID: "pc-1440-ssot-required",
                message: "target_environment must strictly be 'PC-Desktop-1440' (got '\(spec.targetEnvironment)')",
                path: "target_environment"
            ))
        }

        // 2. UUIDv4 Validity
        if UUID(uuidString: spec.uuid) == nil {
            defects.append(PlanningLintDefect(
                ruleID: "uuid-v4-format",
                message: "Page UUID '\(spec.uuid)' is not a valid UUIDv4",
                path: "uuid"
            ))
        }
        if UUID(uuidString: spec.tenantUuid) == nil {
            defects.append(PlanningLintDefect(
                ruleID: "tenant-uuid-format",
                message: "Tenant UUID '\(spec.tenantUuid)' is not a valid UUIDv4",
                path: "tenant_uuid"
            ))
        }
        if UUID(uuidString: spec.shellUuid) == nil {
            defects.append(PlanningLintDefect(
                ruleID: "shell-uuid-format",
                message: "Shell UUID '\(spec.shellUuid)' is not a valid UUIDv4",
                path: "shell_uuid"
            ))
        }

        // 3. Archetype Validity
        if !Self.allowedArchetypes.contains(spec.archetype) {
            defects.append(PlanningLintDefect(
                ruleID: "archetype-canonical",
                message: "Archetype '\(spec.archetype)' must be one of \(Self.allowedArchetypes.sorted())",
                path: "archetype"
            ))
        }

        // 4. Semantic Primitives Restriction & Zero-CSS Check
        for block in spec.blocks {
            if !Self.allowedPrimitives.contains(block.primitive) {
                defects.append(PlanningLintDefect(
                    ruleID: "semantic-primitive-contract",
                    message: "Block primitive '\(block.primitive)' is invalid. Allowed: \(Self.allowedPrimitives.sorted())",
                    path: "blocks.\(block.id).primitive"
                ))
            }

            // Zero-CSS checks
            if let desc = block.description {
                checkZeroCSS(text: desc, path: "blocks.\(block.id).description", into: &defects)
            }
        }

        // 5. States Parity Check
        if spec.states["ready"] == nil {
            defects.append(PlanningLintDefect(
                ruleID: "ready-state-required",
                message: "PageSpec must have a 'ready' active state",
                path: "states.ready"
            ))
        }

        for (stateName, stateDef) in spec.states where FSMGraph.faultStates.contains(stateName) {
            if stateDef.recovery == nil {
                defects.append(PlanningLintDefect(
                    ruleID: "fault-state-recovery-required",
                    message: "Fault state '\(stateName)' must define a 'recovery' contract",
                    path: "states.\(stateName).recovery"
                ))
            }
        }

        return defects
    }

    private func checkZeroCSS(text: String, path: String, into defects: inout [PlanningLintDefect]) {
        let bannedPatterns = ["#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\\b", "\\b\\d+px\\b", "\\b\\d+rem\\b", "style\\s*="]
        for pattern in bannedPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                if regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                    defects.append(PlanningLintDefect(
                        ruleID: "zero-css-violation",
                        message: "Inline styling, hex color, or raw CSS units detected in text ('\(text)')",
                        path: path
                    ))
                    break
                }
            } catch {}
        }
    }
}
