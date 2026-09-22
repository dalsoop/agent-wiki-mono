import Foundation

public enum DiffClassification: String, Sendable {
    case breaking = "BREAKING"
    case additive = "ADDITIVE"
}

public struct ContractDefect: Sendable, CustomStringConvertible {
    public let classification: DiffClassification
    public let code: String
    public let path: String
    public let message: String

    public init(classification: DiffClassification, code: String, path: String, message: String) {
        self.classification = classification
        self.code = code
        self.path = path
        self.message = message
    }

    public var description: String {
        "[\(classification.rawValue)] \(code) (\(path)): \(message)"
    }
}

/// Semantic Contract Differ detecting breaking vs additive changes between two PageSpecs
public struct SemanticContractDiffer: Sendable {
    public let base: PageSpec
    public let head: PageSpec

    public init(base: PageSpec, head: PageSpec) {
        self.base = base
        self.head = head
    }

    public struct DiffResult: Sendable {
        public let breaking: [ContractDefect]
        public let additive: [ContractDefect]
        public var hasBreakingChanges: Bool { !breaking.isEmpty }
    }

    public func diff() -> DiffResult {
        var breaking: [ContractDefect] = []
        var additive: [ContractDefect] = []

        // 1. Diff Blocks
        let baseBlocks = Dictionary(uniqueKeysWithValues: base.blocks.map { ($0.id, $0) })
        let headBlocks = Dictionary(uniqueKeysWithValues: head.blocks.map { ($0.id, $0) })

        for (id, block) in baseBlocks {
            if let headBlock = headBlocks[id] {
                if block.primitive != headBlock.primitive {
                    breaking.append(ContractDefect(
                        classification: .breaking,
                        code: "BLOCK_PRIMITIVE_MUTATED",
                        path: "blocks.\(id).primitive",
                        message: "Block '\(id)' primitive changed from '\(block.primitive)' to '\(headBlock.primitive)'"
                    ))
                }
            } else {
                breaking.append(ContractDefect(
                    classification: .breaking,
                    code: "BLOCK_REMOVED",
                    path: "blocks.\(id)",
                    message: "Existing block '\(id)' was removed"
                ))
            }
        }

        for (id, _) in headBlocks where baseBlocks[id] == nil {
            additive.append(ContractDefect(
                classification: .additive,
                code: "BLOCK_ADDED",
                path: "blocks.\(id)",
                message: "New block '\(id)' was added"
            ))
        }

        // 2. Diff States
        for (stateName, stateDef) in base.states {
            if let headStateDef = head.states[stateName] {
                // Check recovery action removal
                if stateDef.recovery != nil && headStateDef.recovery == nil {
                    breaking.append(ContractDefect(
                        classification: .breaking,
                        code: "RECOVERY_REMOVED",
                        path: "states.\(stateName).recovery",
                        message: "Recovery contract removed from state '\(stateName)'"
                    ))
                }
            } else {
                breaking.append(ContractDefect(
                    classification: .breaking,
                    code: "STATE_REMOVED",
                    path: "states.\(stateName)",
                    message: "State '\(stateName)' was removed"
                ))
            }
        }

        for (stateName, _) in head.states where base.states[stateName] == nil {
            additive.append(ContractDefect(
                classification: .additive,
                code: "STATE_ADDED",
                path: "states.\(stateName)",
                message: "New state '\(stateName)' was added"
            ))
        }

        // 3. Diff Route Contract Carry Params
        let baseCarry = base.routeContract?.inbound?.carry ?? [:]
        let headCarry = head.routeContract?.inbound?.carry ?? [:]

        for (param, _) in baseCarry where headCarry[param] == nil {
            breaking.append(ContractDefect(
                classification: .breaking,
                code: "CARRY_PARAM_REMOVED",
                path: "route_contract.inbound.carry.\(param)",
                message: "Inbound route carry parameter '\(param)' was removed"
            ))
        }

        for (param, _) in headCarry where baseCarry[param] == nil {
            additive.append(ContractDefect(
                classification: .additive,
                code: "CARRY_PARAM_ADDED",
                path: "route_contract.inbound.carry.\(param)",
                message: "New inbound route carry parameter '\(param)' was added"
            ))
        }

        return DiffResult(breaking: breaking, additive: additive)
    }
}
