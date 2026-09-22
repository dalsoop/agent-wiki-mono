import GameRealtimeProtocolKit

public enum SystemStage:
    UInt16,
    CaseIterable,
    Hashable,
    Codable,
    Sendable,
    Comparable
{
    case input = 100
    case simulation = 200
    case collision = 300
    case cleanup = 400

    public static func < (lhs: SystemStage, rhs: SystemStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SystemScheduleError: Error, Equatable, Sendable {
    case duplicateIdentifier(UInt32)
    case duplicateStageOrder(stage: SystemStage, systemOrder: UInt16)
}

public struct SystemSchedule: Hashable, Codable, Sendable {
    public struct Entry: Hashable, Codable, Sendable, Comparable {
        public let identifier: UInt32
        public let stage: SystemStage
        public let systemOrder: UInt16

        public init(
            identifier: UInt32,
            stage: SystemStage,
            systemOrder: UInt16
        ) {
            self.identifier = identifier
            self.stage = stage
            self.systemOrder = systemOrder
        }

        public static func < (lhs: Entry, rhs: Entry) -> Bool {
            if lhs.stage != rhs.stage {
                return lhs.stage < rhs.stage
            }
            if lhs.systemOrder != rhs.systemOrder {
                return lhs.systemOrder < rhs.systemOrder
            }
            return lhs.identifier < rhs.identifier
        }
    }

    public static let standardV1 = SystemSchedule(
        validatedEntries: [
            Entry(identifier: 100, stage: .input, systemOrder: 0),
            Entry(identifier: 200, stage: .simulation, systemOrder: 0),
            Entry(identifier: 300, stage: .collision, systemOrder: 0),
            Entry(identifier: 400, stage: .cleanup, systemOrder: 0),
        ]
    )

    public let orderedEntries: [Entry]

    public init<Entries: Collection>(entries: Entries) throws
    where Entries.Element == Entry {
        let ordered = entries.sorted()
        var identifiers: [UInt32] = []
        var previous: Entry?
        for entry in ordered {
            guard !identifiers.contains(entry.identifier) else {
                throw SystemScheduleError.duplicateIdentifier(
                    entry.identifier
                )
            }
            if let previous,
               previous.stage == entry.stage,
               previous.systemOrder == entry.systemOrder {
                throw SystemScheduleError.duplicateStageOrder(
                    stage: entry.stage,
                    systemOrder: entry.systemOrder
                )
            }
            identifiers.append(entry.identifier)
            previous = entry
        }
        orderedEntries = ordered
    }

    public func commandKey(
        forSystemIdentifier identifier: UInt32,
        sequence: UInt32
    ) -> CommandKey? {
        guard let entry = orderedEntries.first(where: {
            $0.identifier == identifier
        }) else {
            return nil
        }
        return CommandKey(
            stage: entry.stage.rawValue,
            systemOrder: entry.systemOrder,
            sequence: sequence
        )
    }

    private init(validatedEntries: [Entry]) {
        orderedEntries = validatedEntries
    }
}
