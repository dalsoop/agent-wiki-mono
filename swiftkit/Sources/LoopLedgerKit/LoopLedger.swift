import Foundation
import StateRootKit

public struct LoopLedger: Sendable {
    public enum LedgerError: Error, Equatable {
        case invalidLoopID
        case invalidVerdict
        case loopNotFound
        case writeFailed
    }

    public let root: String

    public init(root: String = StateRootKit.path("loops")) {
        self.root = (root as NSString).expandingTildeInPath
    }

    public func snapshot() -> LoopLedgerSnapshot {
        var diagnostics: [LoopDiagnostic] = []
        let nodes = scanDirectory(root, relativeBase: "", diagnostics: &diagnostics)
        let details = flatten(nodes).filter { $0.isLoop || $0.isRelease }.map { node in
            readDetail(node, diagnostics: &diagnostics)
        }
        let projects = projectSummaries(details.filter { $0.node.isLoop })
        return LoopLedgerSnapshot(
            root: root,
            nodes: nodes,
            loops: details,
            projects: projects,
            diagnostics: diagnostics
        )
    }

    public func detail(id: String) -> LoopDetail? {
        snapshot().detail(id: id)
    }

    public func release(id: String) -> LoopReleaseChecklist? {
        snapshot().detail(id: id)?.release
    }

    public func appendFeedback(
        loopID: String,
        artifact: String,
        verdict: String,
        comment: String = "",
        at: Date = Date()
    ) throws {
        guard verdict == "positive" || verdict == "negative" else {
            throw LedgerError.invalidVerdict
        }
        guard let directory = safeDirectory(for: loopID) else { throw LedgerError.invalidLoopID }
        let hasLoop = FileManager.default.fileExists(
            atPath: (directory as NSString).appendingPathComponent("loop.json"))
        let hasRelease = FileManager.default.fileExists(
            atPath: (directory as NSString).appendingPathComponent("release.json"))
        guard hasLoop || hasRelease else {
            throw LedgerError.loopNotFound
        }

        let entry = LoopFeedbackEntry(
            artifact: artifact,
            verdict: verdict,
            comment: comment,
            by: "human",
            at: ISO8601DateFormatter().string(from: at)
        )
        let data = try JSONEncoder().encode(entry)
        guard var line = String(data: data, encoding: .utf8) else { throw LedgerError.writeFailed }
        line += "\n"
        let path = (directory as NSString).appendingPathComponent("feedback.jsonl")
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            do {
                try Data(line.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                throw LedgerError.writeFailed
            }
        }
    }

    public static func runningPhases(_ rounds: [LoopRound]) -> Set<String> {
        var started: Set<String> = []
        var completed: Set<String> = []
        for round in rounds {
            if round.status == "started" {
                started.insert(round.phase)
            } else if round.score != nil || round.note != nil {
                completed.insert(round.phase)
            }
        }
        return started.subtracting(completed)
    }

    private func safeDirectory(for loopID: String) -> String? {
        guard !loopID.isEmpty, !loopID.hasPrefix("/") else { return nil }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        let candidate = rootURL.appendingPathComponent(loopID, isDirectory: true).standardizedFileURL
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(prefix) else { return nil }
        return candidate.path
    }

    private func scanDirectory(
        _ directory: String,
        relativeBase: String,
        diagnostics: inout [LoopDiagnostic]
    ) -> [LoopNode] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        return names.sorted().compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            let path = (directory as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }

            let id = relativeBase.isEmpty ? name : "\(relativeBase)/\(name)"
            let isLoop = fm.fileExists(atPath: (path as NSString).appendingPathComponent("loop.json"))
            let isRelease = fm.fileExists(atPath: (path as NSString).appendingPathComponent("release.json"))
            let children = (isLoop || isRelease)
                ? []
                : scanDirectory(path, relativeBase: id, diagnostics: &diagnostics)
            return LoopNode(
                id: id,
                path: path,
                name: name,
                isLoop: isLoop,
                isRelease: isRelease,
                children: children
            )
        }
    }

    private func flatten(_ nodes: [LoopNode]) -> [LoopNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    private func readDetail(
        _ node: LoopNode,
        diagnostics allDiagnostics: inout [LoopDiagnostic]
    ) -> LoopDetail {
        var diagnostics: [LoopDiagnostic] = []
        var definition: LoopDefinition? = node.isLoop
            ? decode("loop.json", at: node.path, diagnostics: &diagnostics)
            : nil
        if definition?.id.isEmpty == true { definition?.id = node.id }
        let state: LoopState? = node.isLoop
            ? decode("state.json", at: node.path, missingIsDiagnostic: false, diagnostics: &diagnostics)
            : nil
        let release: LoopReleaseChecklist? = node.isRelease
            ? decode("release.json", at: node.path, diagnostics: &diagnostics)
            : nil
        let rounds = readRounds(at: node.path, diagnostics: &diagnostics)
        let feedback = readJSONLines(
            "feedback.jsonl",
            at: node.path,
            as: LoopFeedbackEntry.self,
            diagnostics: &diagnostics
        )
        allDiagnostics.append(contentsOf: diagnostics)
        return LoopDetail(
            node: node,
            definition: definition,
            state: state,
            rounds: rounds,
            feedback: feedback,
            release: release,
            diagnostics: diagnostics
        )
    }

    private func decode<T: Decodable>(
        _ filename: String,
        at directory: String,
        missingIsDiagnostic: Bool = true,
        diagnostics: inout [LoopDiagnostic]
    ) -> T? {
        let path = (directory as NSString).appendingPathComponent(filename)
        guard let data = FileManager.default.contents(atPath: path) else {
            if missingIsDiagnostic {
                diagnostics.append(.init(severity: .warning, path: path, message: "파일을 읽을 수 없습니다"))
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            diagnostics.append(.init(severity: .error, path: path, message: error.localizedDescription))
            return nil
        }
    }

    private func readRounds(
        at directory: String,
        diagnostics: inout [LoopDiagnostic]
    ) -> [LoopRound] {
        let filename = "rounds.jsonl"
        let path = (directory as NSString).appendingPathComponent(filename)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").enumerated().compactMap { index, line in
            do {
                guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    throw CocoaError(.propertyListReadCorrupt)
                }
                let scorecard = (object["scorecard"] as? [String: Any] ?? [:]).compactMap { name, raw in
                    number(raw).map { LoopScoreItem(name: name, value: $0) }
                }.sorted { $0.name < $1.name }
                let round = string(object["round"])
                let phase = object["phase"] as? String ?? round.map { "r\($0)" } ?? "?"
                return LoopRound(
                    id: "\(index)|\(phase)",
                    round: round,
                    phase: phase,
                    role: object["role"] as? String ?? object["judge"] as? String,
                    agent: object["agent"] as? String,
                    status: object["status"] as? String,
                    score: number(object["score"]),
                    blockers: object["blockers"] as? [String] ?? [],
                    note: object["note"] as? String ?? object["notes"] as? String,
                    evidencePath: object["evidencePath"] as? String ?? object["evidence"] as? String,
                    target: object["target"] as? [String] ?? [],
                    rubricAxis: object["rubricAxis"] as? String ?? object["axis"] as? String,
                    scorecard: scorecard,
                    reads: object["reads"] as? [String] ?? [],
                    filesChanged: object["filesChanged"] as? [String] ?? [],
                    startedAt: object["startedAt"] as? String,
                    endedAt: object["endedAt"] as? String
                )
            } catch {
                diagnostics.append(.init(
                    severity: .error,
                    path: "\(path):\(index + 1)",
                    message: error.localizedDescription
                ))
                return nil
            }
        }
    }

    private func readJSONLines<T: Decodable>(
        _ filename: String,
        at directory: String,
        as type: T.Type,
        diagnostics: inout [LoopDiagnostic]
    ) -> [T] {
        let path = (directory as NSString).appendingPathComponent(filename)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").enumerated().compactMap { index, line in
            do {
                return try JSONDecoder().decode(T.self, from: Data(line.utf8))
            } catch {
                diagnostics.append(.init(
                    severity: .error,
                    path: "\(path):\(index + 1)",
                    message: error.localizedDescription
                ))
                return nil
            }
        }
    }

    private func projectSummaries(_ loops: [LoopDetail]) -> [LoopProjectSummary] {
        Dictionary(grouping: loops) { $0.id.split(separator: "/").first.map(String.init) ?? $0.id }
            .map { project, items in
                let statuses = items.map { $0.state?.status ?? "unknown" }
                return LoopProjectSummary(
                    id: project,
                    loopCount: items.count,
                    runningCount: statuses.filter { $0 == "running" }.count,
                    blockedCount: statuses.filter(Self.blockingStatuses.contains).count,
                    convergedCount: statuses.filter { $0 == "converged" }.count,
                    rollupStatus: Self.worstStatus(statuses)
                )
            }
            .sorted { lhs, rhs in
                let left = Self.statusRank[lhs.rollupStatus] ?? 99
                let right = Self.statusRank[rhs.rollupStatus] ?? 99
                return left == right ? lhs.id < rhs.id : left < right
            }
    }

    private static let blockingStatuses: Set<String> = ["error", "budget_exhausted", "stagnated", "stopped"]
    private static let statusRank: [String: Int] = [
        "error": 0,
        "budget_exhausted": 1,
        "stagnated": 2,
        "stopped": 3,
        "running": 4,
        "converged": 5,
        "green": 6,
        "unknown": 7,
    ]

    private static func worstStatus(_ statuses: [String]) -> String {
        statuses.min { (statusRank[$0] ?? 99) < (statusRank[$1] ?? 99) } ?? "unknown"
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}
