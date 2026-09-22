import Foundation

public struct GameSimulationEventBuffer<Payload>: Sendable
where Payload: Codable & Equatable & Sendable {
    public let capacity: Int
    public private(set) var events: [GameSimulationEventEnvelope<Payload>]

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        events = []
    }

    public mutating func append(_ event: GameSimulationEventEnvelope<Payload>) {
        guard capacity > 0 else { return }

        if event.urgency != .urgent,
           let key = event.coalescingKey,
           let index = events.firstIndex(where: {
               $0.urgency != .urgent
                   && $0.channel == event.channel
                   && $0.coalescingKey == key
           }) {
            events.remove(at: index)
        }
        events.append(event)

        while events.count > capacity {
            if let index = events.firstIndex(where: { $0.urgency != .urgent }) {
                events.remove(at: index)
            } else {
                events.removeFirst()
            }
        }
    }

    public mutating func removeAll() {
        events.removeAll(keepingCapacity: true)
    }
}
