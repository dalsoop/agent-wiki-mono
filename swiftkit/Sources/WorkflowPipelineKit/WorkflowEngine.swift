import Foundation
import ContentAddressedAssetKit

public enum WorkflowEngineError: LocalizedError, Equatable, Sendable {
    case schemaMismatch(expected: String, actual: String)
    case stageNotFound(String)
    case slotNotFound(String)
    case emptyAssetHash
    case transitionBlocked(targetStageID: String, missingSlotIDs: [String])

    public var errorDescription: String? {
        switch self {
        case .schemaMismatch(let expected, let actual):
            return "Schema mismatch: expected '\(expected)', actual '\(actual)'"
        case .stageNotFound(let stageID):
            return "Stage '\(stageID)' not found in schema"
        case .slotNotFound(let slotID):
            return "Slot '\(slotID)' not found in schema"
        case .emptyAssetHash:
            return "Asset hash cannot be empty"
        case .transitionBlocked(let targetStageID, let missingSlotIDs):
            return "Cannot transition to stage '\(targetStageID)': missing required slot(s): \(missingSlotIDs.joined(separator: ", "))"
        }
    }
}

public struct WorkflowEngine: Sendable {
    public init() {}

    public static func bind(
        slotID: String,
        assetHash: String,
        in instance: inout WorkflowInstance,
        against schema: PipelineSchema
    ) throws {
        guard schema.id == instance.schemaID else {
            throw WorkflowEngineError.schemaMismatch(expected: schema.id, actual: instance.schemaID)
        }
        guard schema.slot(id: slotID) != nil else {
            throw WorkflowEngineError.slotNotFound(slotID)
        }
        let trimmed = assetHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WorkflowEngineError.emptyAssetHash
        }
        instance.boundSlots[slotID] = trimmed
    }

    public static func bind(
        slotID: String,
        asset: AssetObject,
        in instance: inout WorkflowInstance,
        against schema: PipelineSchema
    ) throws {
        try bind(slotID: slotID, assetHash: asset.hash, in: &instance, against: schema)
    }

    public static func unbind(
        slotID: String,
        in instance: inout WorkflowInstance
    ) {
        instance.boundSlots.removeValue(forKey: slotID)
    }

    public static func transition(
        to targetStageID: String,
        in instance: inout WorkflowInstance,
        against schema: PipelineSchema
    ) throws {
        guard schema.id == instance.schemaID else {
            throw WorkflowEngineError.schemaMismatch(expected: schema.id, actual: instance.schemaID)
        }
        guard schema.stage(id: targetStageID) != nil else {
            throw WorkflowEngineError.stageNotFound(targetStageID)
        }
        let check = instance.canTransition(to: targetStageID, in: schema)
        guard check.canTransition else {
            throw WorkflowEngineError.transitionBlocked(targetStageID: targetStageID, missingSlotIDs: check.missingSlots)
        }
        instance.currentStageID = targetStageID
    }
}
