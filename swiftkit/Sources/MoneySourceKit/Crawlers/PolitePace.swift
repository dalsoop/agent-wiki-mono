import Foundation

/// 기업마당을 한 줄로만 두드린다. 병렬·짧은 간격은 차단 원인이다.
public struct PolitePace: Sendable {
    public var minPageGap: TimeInterval
    public var maxPageGap: TimeInterval
    public var minFileGap: TimeInterval
    public var maxFileGap: TimeInterval
    public var restEvery: Int
    public var minRest: TimeInterval
    public var maxRest: TimeInterval

    public static let standard = PolitePace(
        minPageGap: 2.6,
        maxPageGap: 4.2,
        minFileGap: 1.4,
        maxFileGap: 2.4,
        restEvery: 12,
        minRest: 22,
        maxRest: 38
    )

    public init(
        minPageGap: TimeInterval,
        maxPageGap: TimeInterval,
        minFileGap: TimeInterval,
        maxFileGap: TimeInterval,
        restEvery: Int,
        minRest: TimeInterval,
        maxRest: TimeInterval
    ) {
        self.minPageGap = minPageGap
        self.maxPageGap = maxPageGap
        self.minFileGap = minFileGap
        self.maxFileGap = maxFileGap
        self.restEvery = restEvery
        self.minRest = minRest
        self.maxRest = maxRest
    }

    public func pageGapNanoseconds() -> UInt64 { jitter(minPageGap, maxPageGap) }
    public func fileGapNanoseconds() -> UInt64 { jitter(minFileGap, maxFileGap) }
    public func restNanoseconds() -> UInt64 { jitter(minRest, maxRest) }

    private func jitter(_ lo: TimeInterval, _ hi: TimeInterval) -> UInt64 {
        let span = max(hi - lo, 0)
        let value = lo + TimeInterval.random(in: 0...max(span, 0.01))
        return UInt64(value * 1_000_000_000)
    }
}
