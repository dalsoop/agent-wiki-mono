#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// 4레인 ANSI 이중 버퍼링 실시간 진행률 및 Non-TTY 폴백을 지원하는 TUI 엔진.
public final class LintTUIEngine: Sendable {
    public static let shared = LintTUIEngine()

    public struct WorkerState: Sendable, Equatable {
        public let lane: Int
        public let app: String
        public let rule: String
        public let elapsedMs: Double
        public let isSubprocess: Bool

        public init(lane: Int, app: String, rule: String, elapsedMs: Double, isSubprocess: Bool = false) {
            self.lane = lane
            self.app = app
            self.rule = rule
            self.elapsedMs = elapsedMs
            self.isSubprocess = isSubprocess
        }
    }

    public struct ViolationItem: Sendable, Equatable {
        public let app: String
        public let rule: String
        public let message: String
        public let isP0: Bool

        public init(app: String, rule: String, message: String, isP0: Bool = false) {
            self.app = app
            self.rule = rule
            self.message = message
            self.isP0 = isP0
        }
    }

    public typealias OutputSink = @Sendable (String) -> Void

    public let isTTY: Bool
    private let sink: OutputSink

    private struct State: Sendable {
        var isRunning: Bool = false
        var totalApps: Int = 0
        var completedApps: Int = 0
        var totalFiles: Int = 0
        var completedFiles: Int = 0
        var violationsCount: Int = 0
        var p0Count: Int = 0
        var startTime: DispatchTime = .now()
        var lastRateCalcTime: DispatchTime = .now()
        var lastCompletedFilesForRate: Int = 0
        var emaRate: Double = 0.0
        var activeWorkerLanes: [Int: WorkerState] = [:]
        var slowestTickerQueue: [String] = []
        var activeViolationsQueue: [ViolationItem] = []
        var renderedLinesCount: Int = 0
        var lastNonTTYLogFiles: Int = 0
    }

    private let state = LockedState(State())
    private let timerQueue = DispatchQueue(label: "com.gujo.lint.tui", qos: .userInteractive)

    private struct CancellationHolder: Sendable {
        var cancelAction: (@Sendable () -> Void)?
    }
    private let cancellable = LockedState(CancellationHolder())

    private final class TimerHolder: Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var timer: DispatchSourceTimer?

        init(_ timer: DispatchSourceTimer) {
            self.timer = timer
        }

        func cancel() {
            lock.lock()
            let current = timer
            timer = nil
            lock.unlock()
            current?.cancel()
        }
    }
    private let nonTTYInterval: Int = 100

    public init(isTTY: Bool? = nil, sink: OutputSink? = nil) {
        if let customTTY = isTTY {
            self.isTTY = customTTY
        } else {
            self.isTTY = isatty(STDOUT_FILENO) != 0
        }

        if let customSink = sink {
            self.sink = customSink
        } else {
            self.sink = { text in
                FileHandle.standardOutput.write(Data(text.utf8))
            }
        }
    }

    public func start(totalFiles: Int, totalApps: Int = 0, workerCount: Int = 4) {
        let now = DispatchTime.now()
        state.withLock { s in
            s.totalFiles = totalFiles
            s.totalApps = totalApps
            s.completedFiles = 0
            s.completedApps = 0
            s.violationsCount = 0
            s.p0Count = 0
            s.startTime = now
            s.lastRateCalcTime = now
            s.lastCompletedFilesForRate = 0
            s.emaRate = 0.0
            s.activeWorkerLanes.removeAll()
            s.slowestTickerQueue.removeAll()
            s.activeViolationsQueue.removeAll()
            s.renderedLinesCount = 0
            s.lastNonTTYLogFiles = 0
            s.isRunning = true
        }

        if isTTY {
            sink("\u{001B}[?25l") // Hide cursor
            let t = DispatchSource.makeTimerSource(queue: timerQueue)
            t.schedule(deadline: .now(), repeating: .milliseconds(66))
            t.setEventHandler { [weak self] in
                self?.renderFrame()
            }
            t.resume()
            let holder = TimerHolder(t)
            cancellable.withLock { c in
                c.cancelAction = {
                    holder.cancel()
                }
            }
        } else {
            let appDesc = totalApps > 0 ? "\(totalApps) apps" : "monorepo"
            sink("[LINT] Scan started: \(totalFiles) files across \(appDesc)\n")
        }
    }

    public func updateWorker(lane: Int, app: String, rule: String, elapsedMs: Double, isSubprocess: Bool = false) {
        state.withLock { s in
            let w = WorkerState(lane: lane, app: app, rule: rule, elapsedMs: elapsedMs, isSubprocess: isSubprocess)
            s.activeWorkerLanes[lane] = w
            if elapsedMs >= 300 || isSubprocess {
                Self.appendTickerItem(&s.slowestTickerQueue, rule: rule, app: app, elapsedMs: elapsedMs, isSubprocess: isSubprocess)
            }
        }
    }

    public func recordSlowRule(rule: String, app: String, elapsedMs: Double, isSubprocess: Bool = false) {
        state.withLock { s in
            Self.appendTickerItem(&s.slowestTickerQueue, rule: rule, app: app, elapsedMs: elapsedMs, isSubprocess: isSubprocess)
        }
    }

    public func recordViolation(app: String, rule: String, message: String, isP0: Bool = false) {
        let violation = ViolationItem(app: app, rule: rule, message: message, isP0: isP0)
        state.withLock { s in
            s.violationsCount += 1
            s.p0Count += (isP0 ? 1 : 0)
            Self.enqueueViolation(&s.activeViolationsQueue, item: violation)
        }

        if !isTTY {
            let level = isP0 ? "[ERROR:P0]" : "[WARN]"
            sink("\(level) \(app) - \(rule): \(message)\n")
        }
    }

    public func advanceFile(count: Int = 1) {
        let notifyLog: String? = state.withLock { s in
            s.completedFiles += count
            let intervalReached = (s.completedFiles - s.lastNonTTYLogFiles) >= nonTTYInterval
            let allCompleted = s.completedFiles >= s.totalFiles
            let shouldLog = intervalReached || allCompleted
            if !isTTY && shouldLog {
                s.lastNonTTYLogFiles = s.completedFiles
                let elapsedSec = Double(DispatchTime.now().uptimeNanoseconds - s.startTime.uptimeNanoseconds) / 1_000_000_000.0
                let rate = elapsedSec > 0 ? Double(s.completedFiles) / elapsedSec : 0
                let pct = (Double(s.completedFiles) / Double(max(1, s.totalFiles))) * 100.0
                let etaSec = rate > 0 ? Double(s.totalFiles - s.completedFiles) / rate : 0
                return String(format: "[LINT] %d/%d files (%.1f%%) * %.0f files/s - ETA: %.1fs - Violations: %d\n",
                              s.completedFiles, s.totalFiles, pct, rate, etaSec, s.violationsCount)
            }
            return nil
        }
        if let log = notifyLog {
            sink(log)
        }
    }

    public func advanceApp(count: Int = 1) {
        state.withLock { s in
            s.completedApps += count
        }
    }

    public func renderFrame() {
        guard isTTY else { return }

        let outputText: String = state.withLock { s in
            guard s.isRunning else { return "" }

            var buffer = ""
            if s.renderedLinesCount > 0 {
                buffer += "\u{001B}[\(s.renderedLinesCount)A"
            }

            let now = DispatchTime.now()
            let elapsedSec = Double(now.uptimeNanoseconds - s.startTime.uptimeNanoseconds) / 1_000_000_000.0
            Self.updateRate(&s, now: now, elapsedSec: elapsedSec)

            var lines: [String] = []
            lines.append(contentsOf: Self.buildProgressLines(state: s, elapsedSec: elapsedSec))
            lines.append(contentsOf: Self.buildWorkerLines(state: s))
            lines.append(contentsOf: Self.buildTickerLines(state: s))

            s.renderedLinesCount = lines.count
            buffer += lines.joined(separator: "\n") + "\n"
            return buffer
        }

        if !outputText.isEmpty {
            sink(outputText)
        }
    }

    public func stop(completed: Bool = true) {
        let summaryLog: String = state.withLock { s in
            guard s.isRunning else { return "" }
            s.isRunning = false

            var log = ""
            if isTTY && s.renderedLinesCount > 0 {
                log += "\u{001B}[?25h" // Show cursor
            }
            let elapsedSec = Double(DispatchTime.now().uptimeNanoseconds - s.startTime.uptimeNanoseconds) / 1_000_000_000.0
            let rate = elapsedSec > 0 ? Double(s.completedFiles) / elapsedSec : 0
            log += String(format: "[LINT COMPLETED] Scanned %d files in %.2fs (%.0f files/s) │ Violations: %d (P0: %d)\n",
                          s.completedFiles, elapsedSec, rate, s.violationsCount, s.p0Count)
            return log
        }

        cancellable.withLock { c in
            c.cancelAction?()
            c.cancelAction = nil
        }

        if !summaryLog.isEmpty {
            sink(summaryLog)
        }
    }

    // MARK: - Private Assembly Methods

    private static func enqueueViolation(_ queue: inout [ViolationItem], item: ViolationItem) {
        queue.append(item)
        if queue.count > 3 {
            queue.removeFirst()
        }
    }

    private static func appendTickerItem(
        _ queue: inout [String],
        rule: String,
        app: String,
        elapsedMs: Double,
        isSubprocess: Bool
    ) {
        let tag = isSubprocess ? "Fork" : "\(Int(elapsedMs))ms"
        let item = "\(rule) (\(tag)) on \(app)"
        if !queue.contains(item) {
            queue.append(item)
            if queue.count > 5 {
                queue.removeFirst()
            }
        }
    }

    private static func updateRate(_ s: inout State, now: DispatchTime, elapsedSec: Double) {
        let delta = Double(now.uptimeNanoseconds - s.lastRateCalcTime.uptimeNanoseconds) / 1_000_000_000.0
        guard delta >= 0.2 else { return }
        let deltaFiles = s.completedFiles - s.lastCompletedFilesForRate
        let instantRate = deltaFiles > 0 ? Double(deltaFiles) / delta : 0.0
        s.emaRate = s.emaRate == 0 ? instantRate : (0.3 * instantRate + 0.7 * s.emaRate)
        s.lastRateCalcTime = now
        s.lastCompletedFilesForRate = s.completedFiles
    }

    private static func buildProgressLines(state: State, elapsedSec: Double) -> [String] {
        let effectiveRate = state.emaRate > 0 ? state.emaRate : (elapsedSec > 0 ? Double(state.completedFiles) / elapsedSec : 0.0)
        let remainingFiles = max(0, state.totalFiles - state.completedFiles)
        let etaSec = effectiveRate > 0 ? Double(remainingFiles) / effectiveRate : 0.0
        let pct = Double(state.completedFiles) / Double(max(1, state.totalFiles))
        let pctInt = Int(pct * 100.0)

        let barWidth = 24
        let filledWidth = min(barWidth, max(0, Int(pct * Double(barWidth))))
        let bar = String(repeating: "━", count: filledWidth) + String(repeating: "─", count: max(0, barWidth - filledWidth))

        let appSummary = state.totalApps > 0 ? "\(state.completedApps)/\(state.totalApps) Apps" : "\(state.completedFiles)/\(state.totalFiles) Files"
        let line1 = "\u{001B}[2K\u{001B}[1m[LINT RUN]\u{001B}[0m \(appSummary) (\(pctInt)%) ───\u{001B}[36m\(bar)\u{001B}[0m * \u{001B}[33m\(Int(effectiveRate)) files/s\u{001B}[0m"
        let line2 = String(format: "\u{001B}[2K  Elapsed: %02d:%04.1f │ ETA: %02d:%04.1f │ Scanned: %d/%d files │ Violations: %d (P0: %d)",
                           Int(elapsedSec) / 60, elapsedSec.truncatingRemainder(dividingBy: 60),
                           Int(etaSec) / 60, etaSec.truncatingRemainder(dividingBy: 60),
                           state.completedFiles, state.totalFiles, state.violationsCount, state.p0Count)
        return [line1, line2]
    }

    private static func buildWorkerLines(state: State) -> [String] {
        var lines = ["\u{001B}[2K\u{001B}[1m[Workers]\u{001B}[0m"]
        let sortedLanes = state.activeWorkerLanes.keys.sorted().prefix(4)
        if sortedLanes.isEmpty {
            lines.append("\u{001B}[2K  (Idle)")
            return lines
        }
        for lane in sortedLanes {
            guard let w = state.activeWorkerLanes[lane] else { continue }
            let color: String
            switch w.elapsedMs {
            case let ms where ms >= 500 || w.isSubprocess:
                color = "\u{001B}[31m"
            case 300..<500:
                color = "\u{001B}[33m"
            default:
                color = "\u{001B}[32m"
            }
            let subInfo = w.isSubprocess ? " [FORK]" : ""
            lines.append("\u{001B}[2K  W\(w.lane + 1): \(color)\(w.app)\u{001B}[0m ── \(w.rule) (\(Int(w.elapsedMs))ms\(subInfo))")
        }
        return lines
    }

    private static func buildTickerLines(state: State) -> [String] {
        var lines: [String] = []
        if !state.slowestTickerQueue.isEmpty {
            lines.append("\u{001B}[2K\u{001B}[1m[Slowest Rules Ticker (≥300ms or Fork)]\u{001B}[0m")
            for ticker in state.slowestTickerQueue.suffix(2) {
                lines.append("\u{001B}[2K  [HOT] \u{001B}[31m\(ticker)\u{001B}[0m")
            }
        }
        if !state.activeViolationsQueue.isEmpty {
            lines.append("\u{001B}[2K\u{001B}[1m[Violations Active]\u{001B}[0m")
            for v in state.activeViolationsQueue.suffix(2) {
                let badge = v.isP0 ? "\u{001B}[31m[P0]\u{001B}[0m" : "\u{001B}[33m[WARN]\u{001B}[0m"
                lines.append("\u{001B}[2K  [X] \(badge) \(v.app) ── \(v.rule): \(v.message)")
            }
        }
        return lines
    }
}
