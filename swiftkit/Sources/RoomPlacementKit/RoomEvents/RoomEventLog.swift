import Darwin
import Foundation

public enum RoomEventLogError: Error, Equatable, Sendable {
    case systemCall(String, Int32)
    /// 닫힌 포크(기억 방)에는 이벤트를 더 쓰지 않는다.
    case memoryRoomFrozen
}

public struct RoomEventReadResult: Sendable, Equatable {
    public var events: [RoomEvent]
    public var corruptCount: Int

    public init(events: [RoomEvent], corruptCount: Int) {
        self.events = events
        self.corruptCount = corruptCount
    }
}

public struct RoomEventLog: Sendable {
    public static let fileName = "events.jsonl"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(roomURL: URL) {
        self.fileURL = roomURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// events.jsonl 에 새 이벤트를 원자적으로 추가한다.
    /// flock(LOCK_EX) 로 동시 기록자 간의 seq 순서 및 파일 무결성을 보장한다.
    @discardableResult
    public func append(_ event: RoomEvent) throws -> RoomEvent {
        let dirURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fd = Darwin.open(fileURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw RoomEventLogError.systemCall("open", errno)
        }
        defer {
            _ = flock(fd, LOCK_UN)
            _ = Darwin.close(fd)
        }

        if flock(fd, LOCK_EX) != 0 {
            throw RoomEventLogError.systemCall("flock", errno)
        }

        if containsKind(RoomMemoryGuard.freezeKind) {
            throw RoomEventLogError.memoryRoomFrozen
        }

        // 락을 쥔 상태에서 기존 이벤트들의 최대 seq 를 확인한다.
        let currentMaxSeq = try readMaxSeqLocked(fd: fd)
        var writtenEvent = event
        if writtenEvent.seq <= 0 || writtenEvent.seq <= currentMaxSeq {
            writtenEvent.seq = currentMaxSeq + 1
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var lineData = try encoder.encode(writtenEvent)
        lineData.append(0x0A) // newline '\n'

        let endOffset = Darwin.lseek(fd, 0, SEEK_END)
        guard endOffset >= 0 else {
            throw RoomEventLogError.systemCall("lseek", errno)
        }

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

        return writtenEvent
    }

    /// kind 존재만 본다. 전체 이벤트 배열을 만들지 않는다.
    public func containsKind(_ kind: String) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
            guard let event = try? decoder.decode(RoomEvent.self, from: lineData) else { continue }
            if event.kind == kind { return true }
        }
        return false
    }

    /// since seq 초과의 이벤트들을 읽고, 손상된 줄은 건너뛰며 corruptCount 를 집계한다.
    public func read(since seq: Int = 0) -> RoomEventReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return RoomEventReadResult(events: [], corruptCount: 0)
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return RoomEventReadResult(events: [], corruptCount: 0)
        }

        return parseEvents(from: data, since: seq)
    }

    /// 마지막 n 개 이벤트를 가져온다.
    public func tail(_ n: Int) -> [RoomEvent] {
        let result = read(since: 0)
        let requested = max(0, n)
        if requested >= result.events.count {
            return result.events
        }
        return Array(result.events.suffix(requested))
    }

    private func readMaxSeqLocked(fd: Int32) throws -> Int {
        let fileSize = Darwin.lseek(fd, 0, SEEK_END)
        guard fileSize > 0 else { return 0 }

        // 테일 8KB 버퍼로 파일 끝에서 역순 탐색하여 마지막 유효한 이벤트의 seq를 O(1)로 추출한다.
        let chunkSize = min(Int(fileSize), 8192)
        let offset = fileSize - off_t(chunkSize)
        guard Darwin.lseek(fd, offset, SEEK_SET) >= 0 else {
            throw RoomEventLogError.systemCall("lseek", errno)
        }

        var data = Data(count: chunkSize)
        let readBytes = data.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return 0 }
            var totalRead = 0
            while totalRead < chunkSize {
                let bytes = Darwin.read(fd, baseAddress.advanced(by: totalRead), chunkSize - totalRead)
                if bytes < 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                if bytes == 0 { break }
                totalRead += bytes
            }
            return totalRead
        }
        guard readBytes >= 0 else {
            throw RoomEventLogError.systemCall("read", errno)
        }
        data.count = readBytes

        guard let text = String(data: data, encoding: .utf8) else {
            return try fallbackReadMaxSeqLocked(fd: fd, fileSize: fileSize)
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        // 파일 끝에서부터 역순으로 탐색
        for line in lines.reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let event = try? decoder.decode(RoomEvent.self, from: lineData) else {
                continue
            }
            return event.seq
        }

        // 테일 8KB 내에 완전한 JSON 이벤트가 없으면 전체 파일 폴백
        if chunkSize < Int(fileSize) {
            return try fallbackReadMaxSeqLocked(fd: fd, fileSize: fileSize)
        }
        return 0
    }

    private func fallbackReadMaxSeqLocked(fd: Int32, fileSize: off_t) throws -> Int {
        _ = Darwin.lseek(fd, 0, SEEK_SET)
        var data = Data(count: Int(fileSize))
        let readBytes = data.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return 0 }
            var totalRead = 0
            while totalRead < Int(fileSize) {
                let bytes = Darwin.read(fd, baseAddress.advanced(by: totalRead), Int(fileSize) - totalRead)
                if bytes < 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                if bytes == 0 { break }
                totalRead += bytes
            }
            return totalRead
        }
        guard readBytes >= 0 else {
            throw RoomEventLogError.systemCall("read", errno)
        }
        data.count = readBytes
        let result = parseEvents(from: data, since: 0)
        return result.events.map(\.seq).max() ?? 0
    }

    private func parseEvents(from data: Data, since: Int) -> RoomEventReadResult {
        guard let text = String(data: data, encoding: .utf8) else {
            return RoomEventReadResult(events: [], corruptCount: 1)
        }

        var events: [RoomEvent] = []
        var corruptCount = 0
        let decoder = JSONDecoder()

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            guard let lineData = trimmed.data(using: .utf8) else {
                corruptCount += 1
                continue
            }
            do {
                let event = try decoder.decode(RoomEvent.self, from: lineData)
                if event.seq > since {
                    events.append(event)
                }
            } catch {
                corruptCount += 1
            }
        }

        events.sort { $0.seq < $1.seq }
        return RoomEventReadResult(events: events, corruptCount: corruptCount)
    }
}
