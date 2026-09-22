import Foundation
import StateRootKit

public enum BottleneckCategory: String, Codable, Sendable {
    case redos = "ReDoS"
    case lockWait = "LockWait"
    case ioContention = "IOContention"
    case unboundedScan = "UnboundedScan"
    case subprocessFork = "SubprocessFork"
}

public struct BottleneckEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let ruleId: String
    public let authorAgentId: String
    public let triggerAgentId: String
    public let filePath: String
    public let durationMs: Double
    public let category: BottleneckCategory
    public let callStackSnippet: String
    public let mitigationApplied: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        ruleId: String,
        authorAgentId: String = "agent:fleet",
        triggerAgentId: String = "agent:current",
        filePath: String,
        durationMs: Double,
        category: BottleneckCategory,
        callStackSnippet: String = "",
        mitigationApplied: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.ruleId = ruleId
        self.authorAgentId = authorAgentId
        self.triggerAgentId = triggerAgentId
        self.filePath = filePath
        self.durationMs = durationMs
        self.category = category
        self.callStackSnippet = callStackSnippet
        self.mitigationApplied = mitigationApplied
    }
}

public final class FastBottleneckLedgerEngine: @unchecked Sendable {
    public static let shared = FastBottleneckLedgerEngine()

    private let lock = NSLock()
    private let capacity: Int = 1000
    private var buffer: [BottleneckEvent?]
    private var writeIndex: Int = 0
    private var totalRecorded: Int = 0
    private let ledgerDirectory: URL
    private let ledgerFile: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageDirectory: URL? = nil) {
        self.buffer = Array(repeating: nil, count: 1000)
        let dir: URL
        if let storageDirectory {
            dir = storageDirectory
        } else {
            dir = StateRootKit.url(".agent-lint")
        }
        self.ledgerDirectory = dir
        self.ledgerFile = dir.appendingPathComponent("lint-bottleneck-ledger.jsonl", isDirectory: false)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        do { try FileManager.default.createDirectory(at: ledgerDirectory, withIntermediateDirectories: true) } catch { _ = error }
    }

    public func record(
        ruleId: String,
        authorAgentId: String = "agent:fleet",
        triggerAgentId: String = "agent:current",
        filePath: String,
        durationMs: Double,
        category: BottleneckCategory,
        callStackSnippet: String = "",
        mitigationApplied: String = ""
    ) {
        let event = BottleneckEvent(
            ruleId: ruleId,
            authorAgentId: authorAgentId,
            triggerAgentId: triggerAgentId,
            filePath: filePath,
            durationMs: durationMs,
            category: category,
            callStackSnippet: callStackSnippet,
            mitigationApplied: mitigationApplied
        )

        lock.lock()
        buffer[writeIndex] = event
        writeIndex = (writeIndex + 1) % capacity
        totalRecorded += 1
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let data = try? self.encoder.encode(event) else { return }
            var lineData = data
            lineData.append(0x0A)

            if FileManager.default.fileExists(atPath: self.ledgerFile.path) {
                do {
                    let handle = try FileHandle(forWritingTo: self.ledgerFile)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: lineData)
                } catch {
                    // 절단 방어: 파일이 이미 존재할 때 핸들 획득/추가 실패 시 전체 원장 덮어쓰기(절단) 방지
                }
            } else {
                do {
                    try lineData.write(to: self.ledgerFile, options: .atomic)
                } catch {
                    // 최초 파일 생성 실패 안전 처리
                }
            }
        }
    }

    public func recentEvents(limit: Int = 100) -> [BottleneckEvent] {
        lock.lock()
        defer { lock.unlock() }
        let currentCount = min(totalRecorded, capacity)
        let fetchCount = min(limit, currentCount)
        guard fetchCount > 0 else { return [] }
        var result: [BottleneckEvent] = []
        result.reserveCapacity(fetchCount)
        for i in 0..<fetchCount {
            let idx = (writeIndex - 1 - i + capacity) % capacity
            if let ev = buffer[idx] {
                result.append(ev)
            }
        }
        return result
    }

    /// 디스크의 JSONL 원장 파일(`~/.agent-lint/lint-bottleneck-ledger.jsonl`)에서 직전 발생한 이벤트들을 안전하게 파싱하여 로드
    public func loadRecentEventsFromDisk(limit: Int = 1000) -> [BottleneckEvent] {
        guard FileManager.default.fileExists(atPath: ledgerFile.path) else { return [] }
        guard let content = try? String(contentsOf: ledgerFile, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines)
        var events: [BottleneckEvent] = []

        // 파일의 뒤쪽(최신) 라인부터 역순 파싱
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            do {
                let event = try decoder.decode(BottleneckEvent.self, from: data)
                events.append(event)
                if events.count >= limit {
                    break
                }
            } catch {}
        }

        return events
    }

    public func agentRanking() -> [(agentId: String, totalMs: Double, count: Int)] {
        lock.lock()
        defer { lock.unlock() }

        var dict: [String: (totalMs: Double, count: Int)] = [:]
        let currentCount = min(totalRecorded, capacity)
        for i in 0..<currentCount {
            let idx = (writeIndex - 1 - i + capacity) % capacity
            if let ev = buffer[idx] {
                let current = dict[ev.authorAgentId, default: (0.0, 0)]
                dict[ev.authorAgentId] = (current.totalMs + ev.durationMs, current.count + 1)
            }
        }
        return dict.map { (agentId: $0.key, totalMs: $0.value.totalMs, count: $0.value.count) }
            .sorted { $0.totalMs > $1.totalMs }
    }

    public func hotspotRules(limit: Int = 10) -> [(ruleId: String, totalMs: Double, count: Int)] {
        lock.lock()
        defer { lock.unlock() }

        var dict: [String: (totalMs: Double, count: Int)] = [:]
        let currentCount = min(totalRecorded, capacity)
        for i in 0..<currentCount {
            let idx = (writeIndex - 1 - i + capacity) % capacity
            if let ev = buffer[idx] {
                let current = dict[ev.ruleId, default: (0.0, 0)]
                dict[ev.ruleId] = (current.totalMs + ev.durationMs, current.count + 1)
            }
        }
        let sorted = dict.map { (ruleId: $0.key, totalMs: $0.value.totalMs, count: $0.value.count) }
            .sorted { $0.totalMs > $1.totalMs }
        return Array(sorted.prefix(limit))
    }

    public func reset() {
        lock.lock()
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        totalRecorded = 0
        lock.unlock()
    }
}
