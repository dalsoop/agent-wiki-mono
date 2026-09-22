import Foundation

public struct PipelineSchema: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let stages: [StageSpec]
    public let slots: [DocumentSlotSpec]

    public init(
        id: String,
        title: String,
        stages: [StageSpec],
        slots: [DocumentSlotSpec]
    ) {
        self.id = id
        self.title = title
        self.stages = stages.sorted { $0.order < $1.order }
        self.slots = slots
    }

    public func stage(id: String) -> StageSpec? {
        stages.first { $0.id == id }
    }

    public func slot(id: String) -> DocumentSlotSpec? {
        slots.first { $0.id == id }
    }
}
