import Foundation
import OSLog

/// Tails this process's own unified-logging output (`Logger`/`os_log`) via
/// `OSLogStore`, so a running app can show its recent logs and hand them to the
/// AI alongside a picked element. Scoped to the current process, so it needs no
/// entitlement or Screen Recording permission.
///
/// Wire it up once and start polling:
/// ```swift
/// @StateObject private var logs = InspectorLog()
/// ...
/// .onAppear { inspector.log = logs; logs.start() }
/// ```
@MainActor
public final class InspectorLog: ObservableObject {
    public enum Level: String, Sendable {
        case debug, info, notice, error, fault, unknown
    }

    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let level: Level
        public let category: String
        public let message: String
    }

    /// Rolling buffer, oldest first. Capped at `maxEntries`.
    @Published public private(set) var entries: [Entry] = []
    public var maxEntries = 400
    /// When set, only entries from this subsystem are kept — filters out the
    /// noisy XPC/tccd/OSLogService lines macOS emits into every process, leaving
    /// just your app's own `Logger(subsystem:)` output. nil keeps everything.
    public var subsystem: String?

    private let store: OSLogStore?
    private var lastDate: Date?
    private var pollTask: Task<Void, Never>?

    public init() {
        // Fails only in sandboxes that block the log store; degrade to no logs.
        do {
            self.store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            self.store = nil
        }
    }

    /// Begin polling the log store every `interval` seconds. Idempotent.
    public func start(interval: Double = 1.5) {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func clear() {
        entries.removeAll()
        lastDate = nil
    }

    /// Pull any log entries newer than the last one we saw into `entries`.
    public func refresh() {
        guard let store else { return }
        let since = lastDate ?? Date(timeIntervalSinceNow: -5)
        let position = store.position(date: since)
        // Filter at the store level so we don't even materialize system noise.
        let predicate = subsystem.map { NSPredicate(format: "subsystem == %@", $0) }
        guard let raw = try? store.getEntries(at: position, matching: predicate) else { return }

        var fresh: [Entry] = []
        for case let log as OSLogEntryLog in raw {
            if let last = lastDate, log.date <= last { continue }
            fresh.append(Entry(
                id: UUID(),
                date: log.date,
                level: Self.map(log.level),
                category: log.category,
                message: log.composedMessage))
        }
        guard !fresh.isEmpty else { return }

        lastDate = fresh.last?.date ?? lastDate
        entries.append(contentsOf: fresh)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// The most recent lines, oldest first, formatted for an AI context block.
    public func recentLines(limit: Int = 12) -> [String] {
        entries.suffix(limit).map { "[\($0.level.rawValue)] \($0.message)" }
    }

    private static func map(_ level: OSLogEntryLog.Level) -> Level {
        switch level {
        case .debug:  return .debug
        case .info:   return .info
        case .notice: return .notice
        case .error:  return .error
        case .fault:  return .fault
        default:      return .unknown
        }
    }
}
