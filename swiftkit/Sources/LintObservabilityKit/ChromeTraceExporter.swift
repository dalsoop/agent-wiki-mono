import Foundation

/// Chrome DevTools Trace Event Format (`trace.json`) 생성기.
///
/// Google Chrome `chrome://tracing`, [Perfetto UI](https://ui.perfetto.dev), speedscope 등과
/// 100% 호환되는 계층적 분산 프로파일링 트레이스를 생성합니다.
public enum ChromeTraceExporter {

    /// 단일 트레이스 이벤트 (Phase: X=Complete, B=Begin, E=End, M=Metadata, i=Instant).
    public struct TraceEvent: Codable, Sendable, Equatable {
        public let name: String
        public let cat: String
        public let ph: String
        public let ts: Int64      // 마이크로초 (Microseconds)
        public let dur: Int64?    // 마이크로초 (Microseconds, Complete 이벤트 'X' 전용)
        public let pid: Int
        public let tid: Int
        public let args: [String: String]?

        public init(
            name: String,
            cat: String,
            ph: String,
            ts: Int64,
            dur: Int64? = nil,
            pid: Int = 1,
            tid: Int = 1,
            args: [String: String]? = nil
        ) {
            self.name = name
            self.cat = cat
            self.ph = ph
            self.ts = ts
            self.dur = dur
            self.pid = pid
            self.tid = tid
            self.args = args
        }

        public static func processMetadata(name: String, pid: Int = 1) -> TraceEvent {
            TraceEvent(name: "process_name", cat: "__metadata", ph: "M", ts: 0, pid: pid, tid: 0, args: ["name": name])
        }

        public static func threadMetadata(name: String, pid: Int = 1, tid: Int) -> TraceEvent {
            TraceEvent(name: "thread_name", cat: "__metadata", ph: "M", ts: 0, pid: pid, tid: tid, args: ["name": name])
        }

        public static func complete(
            name: String,
            cat: String,
            tsMicroseconds: Int64,
            durMicroseconds: Int64,
            pid: Int = 1,
            tid: Int = 1,
            args: [String: String]? = nil
        ) -> TraceEvent {
            TraceEvent(name: name, cat: cat, ph: "X", ts: tsMicroseconds, dur: durMicroseconds, pid: pid, tid: tid, args: args)
        }

        public static func instant(
            name: String,
            cat: String,
            tsMicroseconds: Int64,
            pid: Int = 1,
            tid: Int = 1,
            args: [String: String]? = nil
        ) -> TraceEvent {
            TraceEvent(name: name, cat: cat, ph: "i", ts: tsMicroseconds, pid: pid, tid: tid, args: args)
        }
    }

    /// 표준 최상위 JSON 트레이스 봉투.
    public struct TraceEnvelope: Codable, Sendable {
        public let traceEvents: [TraceEvent]
        public let displayTimeUnit: String

        public init(traceEvents: [TraceEvent], displayTimeUnit: String = "ms") {
            self.traceEvents = traceEvents
            self.displayTimeUnit = displayTimeUnit
        }
    }

    /// 이벤트 목록을 Chrome Trace JSON 파일로 원자적 저장합니다.
    public static func export(events: [TraceEvent], to destinationURL: URL) throws {
        let data = try exportData(events: events)
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)
    }

    /// 이벤트 목록을 직렬화된 JSON Data로 반환합니다.
    public static func exportData(events: [TraceEvent]) throws -> Data {
        let envelope = TraceEnvelope(traceEvents: events, displayTimeUnit: "ms")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    /// 이벤트 목록을 직렬화된 JSON 문자열로 반환합니다.
    public static func exportJSONString(events: [TraceEvent]) throws -> String {
        let data = try exportData(events: events)
        guard let str = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return str
    }
}

/// 동시성 환경에서 안전하게 트레이스 이벤트를 수집하는 세션 관리자.
public final class ChromeTraceSession: Sendable {
    private struct State: Sendable {
        var events: [ChromeTraceExporter.TraceEvent] = []
    }
    private let state: LockedState<State>
    private let baseTimestampMicros: Int64

    public init(processName: String = "AgentLintCatalog Runner", threadCount: Int = 4) {
        let nowMicros = Int64(Date().timeIntervalSince1970 * 1_000_000.0)
        self.baseTimestampMicros = nowMicros

        var initialEvents: [ChromeTraceExporter.TraceEvent] = [
            ChromeTraceExporter.TraceEvent.processMetadata(name: processName, pid: 1)
        ]
        for i in 0..<max(1, threadCount) {
            let tid = i + 1
            initialEvents.append(ChromeTraceExporter.TraceEvent.threadMetadata(name: "Worker-\(i) (Core \(i))", pid: 1, tid: tid))
        }
        self.state = LockedState(State(events: initialEvents))
    }

    public func recordEvent(_ event: ChromeTraceExporter.TraceEvent) {
        state.withLock { s in
            s.events.append(event)
        }
    }

    public func recordComplete(
        name: String,
        cat: String,
        startRelativeMicros: Int64,
        durationMicros: Int64,
        pid: Int = 1,
        tid: Int = 1,
        args: [String: String]? = nil
    ) {
        let absoluteTs = baseTimestampMicros + startRelativeMicros
        let event = ChromeTraceExporter.TraceEvent.complete(
            name: name,
            cat: cat,
            tsMicroseconds: absoluteTs,
            durMicroseconds: durationMicros,
            pid: pid,
            tid: tid,
            args: args
        )
        recordEvent(event)
    }

    public func allEvents() -> [ChromeTraceExporter.TraceEvent] {
        state.withLock { s in
            s.events
        }
    }

    public func export(to fileURL: URL) throws {
        let snapshot = allEvents()
        try ChromeTraceExporter.export(events: snapshot, to: fileURL)
    }
}
