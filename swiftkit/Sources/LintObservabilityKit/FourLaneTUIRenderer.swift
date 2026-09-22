import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 4-스윔레인(Swimlane) 실시간 터미널 TUI 렌더러
public final class FourLaneTUIRenderer: Sendable {
    private let isTTY: Bool
    private struct StateLock: Sendable {
        var isRunning: Bool = false
    }
    private let stateLock = LockedState(StateLock())

    public struct State: Sendable {
        public var totalFiles: Int = 0
        public var completedFiles: Int = 0
        public var activeWorkers: [(workerId: Int, currentApp: String)] = []
        public var slowestRules: [(ruleId: String, durationMs: Double)] = []
        public var violationCount: Int = 0
        public var p0Count: Int = 0
        public var filesPerSecond: Double = 0.0
        public var etaSeconds: Double = 0.0

        public init(
            totalFiles: Int = 0,
            completedFiles: Int = 0,
            activeWorkers: [(workerId: Int, currentApp: String)] = [],
            slowestRules: [(ruleId: String, durationMs: Double)] = [],
            violationCount: Int = 0,
            p0Count: Int = 0,
            filesPerSecond: Double = 0.0,
            etaSeconds: Double = 0.0
        ) {
            self.totalFiles = totalFiles
            self.completedFiles = completedFiles
            self.activeWorkers = activeWorkers
            self.slowestRules = slowestRules
            self.violationCount = violationCount
            self.p0Count = p0Count
            self.filesPerSecond = filesPerSecond
            self.etaSeconds = etaSeconds
        }
    }

    public init(forceTTY: Bool? = nil) {
        if let force = forceTTY {
            self.isTTY = force
        } else {
            #if canImport(Darwin) || canImport(Glibc)
            self.isTTY = isatty(STDERR_FILENO) != 0
            #else
            self.isTTY = false
            #endif
        }
    }

    public func start() {
        guard isTTY else { return }
        stateLock.withLock { s in
            s.isRunning = true
        }
        // Hide cursor
        FileHandle.standardError.write(Data("\u{001B}[?25l".utf8))
    }

    public func render(state: State) {
        guard isTTY else { return }

        var buffer = ""
        let bar = makeProgressBar(current: state.completedFiles, total: state.totalFiles)
        let rate = Int(state.filesPerSecond)
        let eta = String(format: "%.1f", state.etaSeconds)
        buffer += "\u{001B}[2K[Phase]   \(bar) * \(rate) files/s (ETA: \(eta)s)\n"
        buffer += "\u{001B}[2K[Workers] \(state.activeWorkers.map { "#\($0.workerId): \($0.currentApp)" }.joined(separator: " │ "))\n"
        buffer += "\u{001B}[2K[P90 Top] \(state.slowestRules.prefix(3).map { "\($0.ruleId) (\(Int($0.durationMs))ms)" }.joined(separator: " │ "))\n"
        buffer += "\u{001B}[2K[Findings] Violations: \(state.violationCount) (P0: \(state.p0Count))\n"
        buffer += "\u{001B}[4A" // Return cursor 4 lines up

        FileHandle.standardError.write(Data(buffer.utf8))
    }

    public func finish() {
        guard isTTY else { return }
        stateLock.withLock { s in
            s.isRunning = false
        }
        // Move down past the 4 rendered lines and show cursor
        var buffer = "\u{001B}[4B\n"
        buffer += "\u{001B}[?25h"
        FileHandle.standardError.write(Data(buffer.utf8))
    }

    private func makeProgressBar(current: Int, total: Int, width: Int = 20) -> String {
        guard total > 0 else { return "[\(String(repeating: "-", count: width))] 0%" }
        let progress = min(1.0, max(0.0, Double(current) / Double(total)))
        let filled = Int(Double(width) * progress)
        let empty = width - filled
        let bar = String(repeating: "=", count: filled) + String(repeating: "-", count: empty)
        let percent = Int(progress * 100)
        return "[\(bar)] \(percent)%"
    }
}
