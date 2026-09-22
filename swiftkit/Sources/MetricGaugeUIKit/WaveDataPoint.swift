import Foundation

public struct WaveDataPoint: Identifiable, Sendable {
    public let id: UUID
    public let index: Int64
    public let amplitude: Double

    public init(id: UUID = UUID(), index: Int64, amplitude: Double) {
        self.id = id
        self.index = index
        self.amplitude = amplitude
    }
}
