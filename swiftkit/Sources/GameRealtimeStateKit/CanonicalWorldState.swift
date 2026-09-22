public struct CanonicalWorldState: Codable, Sendable {
    public var tick: UInt64
    public var epoch: UInt64
    public var seed: UInt64

    public init(tick: UInt64 = 0, epoch: UInt64 = 0, seed: UInt64) {
        self.tick = tick
        self.epoch = epoch
        self.seed = seed
    }
}
