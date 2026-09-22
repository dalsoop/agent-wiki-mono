import Foundation

public struct WorkflowInstance: Codable, Sendable, Equatable {
    public let schemaID: String
    public var currentStageID: String
    public var boundSlots: [String: String]

    public init(
        schemaID: String,
        currentStageID: String,
        boundSlots: [String: String] = [:]
    ) {
        self.schemaID = schemaID
        self.currentStageID = currentStageID
        self.boundSlots = boundSlots
    }

    /// Calculates the readiness percentage based on required document slots (0.0 ~ 100.0).
    public func readinessPercent(against schema: PipelineSchema) -> Double {
        let requiredSlots = schema.slots.filter(\.isRequired)
        guard !requiredSlots.isEmpty else {
            return 100.0
        }
        let filledCount = requiredSlots.filter { slot in
            guard let hash = boundSlots[slot.id] else { return false }
            return !hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return (Double(filledCount) / Double(requiredSlots.count)) * 100.0
    }

    /// Returns the list of missing required document slot specifications.
    public func missingRequiredSlots(against schema: PipelineSchema) -> [DocumentSlotSpec] {
        schema.slots.filter { slot in
            guard slot.isRequired else { return false }
            guard let hash = boundSlots[slot.id] else { return true }
            return hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Evaluates if the workflow instance can transition to the given stage.
    public func canTransition(to targetStageID: String, in schema: PipelineSchema) -> (canTransition: Bool, missingSlots: [String]) {
        guard let stage = schema.stage(id: targetStageID) else {
            return (false, [])
        }
        let missing = stage.requiredSlotIDs.filter { slotID in
            guard let hash = boundSlots[slotID] else { return true }
            return hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return (missing.isEmpty, missing)
    }
}
