import Foundation
import GameRealtimeProtocolKit

public struct DeterminismRunReport: Hashable, Codable, Sendable {
    public let ticks: Int
    public let snapshot: CanonicalSnapshot
    public let canonicalBytes: Data
    public let deterministicStateHash: UInt64

    init(ticks: Int, snapshot: CanonicalSnapshot) {
        self.ticks = ticks
        self.snapshot = snapshot
        canonicalBytes = snapshot.canonicalBytes
        deterministicStateHash = snapshot.deterministicStateHash
    }
}

struct DeterminismRunner: Sendable {
    func run(
        fixture: HeadlessFixture,
        ticks: Int,
        input: CombatInputFrame
    ) throws -> DeterminismRunReport {
        try fixture.run(ticks: ticks, input: input)
    }
}

struct SoakMetricSample: Hashable, Sendable {
    let tick: Int
    let entityCount: Int
    let componentCount: Int
    let queueCount: Int
    let cacheCount: Int
    let checkpointCount: Int
    let checkpointBytes: Int
    let rssBytes: Int
}

struct SoakRunReport: Hashable, Sendable {
    let ticks: Int
    let simulatedSeconds: Int
    let samples: [SoakMetricSample]
    let metricsStable: Bool
    let maximumPositiveSlopeBytesPerTenMinutes: Double
}
