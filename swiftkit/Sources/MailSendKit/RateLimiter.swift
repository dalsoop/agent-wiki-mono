import Foundation

public protocol RateLimitPathing: Sendable {
    var rateLimitFile: URL { get }
    func ensureLayout() throws
}

/// 프로세스·CLI 호출을 가로지르는 1회/초 제한. 디스크에 마지막 발송 시각을 남긴다.
public struct RateLimiter: Sendable {
    public static let interval: TimeInterval = 1

    public let paths: any RateLimitPathing
    private let clock: any MailClock
    public var intervalOverride: TimeInterval?

    public init(
        paths: some RateLimitPathing,
        clock: any MailClock = SystemMailClock(),
        interval: TimeInterval? = nil
    ) {
        self.paths = paths
        self.clock = clock
        self.intervalOverride = interval
    }

    public func waitTurn() async throws {
        try paths.ensureLayout()
        let gap = intervalOverride ?? Self.interval
        let now = clock.now
        if let last = try readLast(), now.timeIntervalSince(last) < gap {
            let remaining = gap - now.timeIntervalSince(last)
            await clock.sleep(seconds: remaining)
        }
        try writeLast(clock.now)
    }

    public func lastSendAt() -> Date? {
        (try? readLast())
    }

    private struct Stamp: Codable {
        var lastSendAt: Date
    }

    private func readLast() throws -> Date? {
        guard FileManager.default.fileExists(atPath: paths.rateLimitFile.path) else { return nil }
        let data = try Data(contentsOf: paths.rateLimitFile)
        return try decoder().decode(Stamp.self, from: data).lastSendAt
    }

    private func writeLast(_ date: Date) throws {
        try encoder().encode(Stamp(lastSendAt: date)).write(to: paths.rateLimitFile, options: .atomic)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
