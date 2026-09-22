import Darwin
import Foundation

// MARK: - 앱 차용 상태

public enum RoomAppBorrowStatus: String, Codable, Sendable, Equatable {
    case active
    case released
    case expired
}

/// 에이전트가 방 안에서 앱을 쓰는 차용 기록. `RoomLeaseLock`(방 PID 락)과 별개다.
public struct RoomAppBorrow: Codable, Sendable, Equatable {
    public static let defaultDuration: TimeInterval = 300

    public let roomID: String
    public let bundleID: String
    public let agent: RoomActor
    public let borrowedAt: Date
    public var expiresAt: Date
    public var status: RoomAppBorrowStatus

    public init(
        roomID: String,
        bundleID: String,
        agent: RoomActor,
        borrowedAt: Date = Date(),
        duration: TimeInterval = RoomAppBorrow.defaultDuration,
        status: RoomAppBorrowStatus = .active
    ) {
        self.roomID = roomID
        self.bundleID = bundleID
        self.agent = agent
        self.borrowedAt = borrowedAt
        self.expiresAt = borrowedAt.addingTimeInterval(duration)
        self.status = status
    }

    /// 같은 앱을 다시 쓰면 `now`부터 duration만큼 연장한다.
    public mutating func renew(
        now: Date = Date(),
        duration: TimeInterval = RoomAppBorrow.defaultDuration
    ) {
        status = .active
        expiresAt = now.addingTimeInterval(duration)
    }

    public func isActive(now: Date = Date()) -> Bool {
        status == .active && now < expiresAt
    }

    public mutating func expire() {
        status = .expired
    }

    public mutating func release() {
        status = .released
    }

    public static func dockObservedBundleIDs(
        roomID: String,
        borrows: [RoomAppBorrow],
        now: Date = Date()
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for b in borrows where b.roomID == roomID && b.isActive(now: now) {
            if seen.insert(b.bundleID).inserted {
                result.append(b.bundleID)
            }
        }
        return result
    }
}

// MARK: - 5분 차용 시계

public enum RoomAppBorrowClock {
    public static let keepDuration: TimeInterval = 5 * 60

    public static func expiresAt(from date: Date) -> Date {
        date.addingTimeInterval(keepDuration)
    }

    public static func isActive(status: RoomAppBorrowStatus, expiresAt: Date, now: Date = Date()) -> Bool {
        status == .active && now < expiresAt
    }
}

// MARK: - append-only JSONL

/// 방 볼트 `raw/app-borrows.jsonl`에 차용 스냅샷을 덧붙인다.
public struct RoomAppBorrowStore: Sendable {
    public static let fileName = "app-borrows.jsonl"
    private var fileManager: FileManager { .default }

    public init() {}

    @discardableResult
    public func append(_ borrow: RoomAppBorrow, in layout: RoomVaultLayout) throws -> RoomAppBorrow {
        try RoomMemoryGuard.assertMutable(roomURL: layout.roomURL)
        let url = try ensureBorrowsFile(in: layout)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var lineData = try encoder.encode(borrow)
        lineData.append(0x0A)

        let fd = Darwin.open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else {
            throw RoomEventLogError.systemCall("open", errno)
        }
        defer { _ = Darwin.close(fd) }

        try lineData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            let total = rawBuffer.count
            while written < total {
                let bytes = Darwin.write(fd, baseAddress.advanced(by: written), total - written)
                if bytes < 0 {
                    if errno == EINTR { continue }
                    throw RoomEventLogError.systemCall("write", errno)
                }
                written += bytes
            }
        }
        _ = Darwin.fsync(fd)
        return borrow
    }

    private func ensureBorrowsFile(in layout: RoomVaultLayout) throws -> URL {
        try fileManager.createDirectory(at: layout.rawDir, withIntermediateDirectories: true)
        let url = layout.appBorrowsFile
        guard fileManager.fileExists(atPath: url.path) else {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o644])
            return url
        }
        return url
    }

    public func read(in layout: RoomVaultLayout) -> [RoomAppBorrow] {
        let url = layout.appBorrowsFile
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [RoomAppBorrow] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            guard let record = try? decoder.decode(RoomAppBorrow.self, from: lineData) else { continue }
            records.append(record)
        }
        return records
    }
}
