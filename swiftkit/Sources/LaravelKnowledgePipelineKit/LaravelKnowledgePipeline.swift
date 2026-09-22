import Foundation
import StateMirrorKit

public enum PipelineHealth: String, Codable, Equatable, Sendable {
    case healthy
    case running
    case stalled
    case warning
    case unavailable
    case failed
}

public struct PipelineSourceSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let health: PipelineHealth
    public let summary: String
    public let detail: String?
    public let completed: Int?
    public let total: Int?
    public let unit: String?
    public let currentTarget: String?
    public let updatedAt: String?
    public let facts: [String: String]

    public struct Progress: Sendable, Equatable {
        public var completed: Int?
        public var total: Int?
        public var unit: String?
        public var currentTarget: String?

        public init(
            completed: Int? = nil,
            total: Int? = nil,
            unit: String? = nil,
            currentTarget: String? = nil
        ) {
            self.completed = completed
            self.total = total
            self.unit = unit
            self.currentTarget = currentTarget
        }
    }

    public init(
        id: String,
        title: String,
        health: PipelineHealth,
        summary: String,
        detail: String?,
        progress: Progress = Progress(),
        updatedAt: String?,
        facts: [String: String]
    ) {
        self.id = id
        self.title = title
        self.health = health
        self.summary = summary
        self.detail = detail
        self.completed = progress.completed
        self.total = progress.total
        self.unit = progress.unit
        self.currentTarget = progress.currentTarget
        self.updatedAt = updatedAt
        self.facts = facts
    }

    public var progressText: String? {
        guard let completed, let total else { return nil }
        let suffix = unit.map { " \($0)" } ?? ""
        return "\(completed)/\(total)\(suffix)"
    }

    public static func unavailable(id: String, title: String) -> Self {
        Self(
            id: id,
            title: title,
            health: .unavailable,
            summary: "unavailable",
            detail: nil,
            updatedAt: nil,
            facts: [:]
        )
    }
}

public struct LaravelKnowledgePipelineSnapshot: Codable, Equatable, Sendable {
    public let graphify: PipelineSourceSnapshot
    public let architecture: PipelineSourceSnapshot
    public let wiki: PipelineSourceSnapshot

    public init(
        graphify: PipelineSourceSnapshot,
        architecture: PipelineSourceSnapshot,
        wiki: PipelineSourceSnapshot
    ) {
        self.graphify = graphify
        self.architecture = architecture
        self.wiki = wiki
    }

    public static let empty = LaravelKnowledgePipelineSnapshot(
        graphify: .unavailable(id: "graphify", title: "Graphify"),
        architecture: .unavailable(
            id: "laravel-architecture",
            title: "Laravel architecture"
        ),
        wiki: .unavailable(id: "gujo-wiki", title: "gujo wiki")
    )
}

public struct LaravelKnowledgePipelineConfiguration: Equatable, Sendable {
    /// 로컬 gujo 개발 트리의 graphify 산출물 기본 경로.
    /// 공용 모듈이므로 소비처는 `graphArtifactURL` / env / 이 상수를 주입해 덮어쓴다.
    public static let standardGraphArtifactPath: String = ((
        "~/Documents/WORK/WORKSPACE/apps/laravel-mono/main/apps/"
            + "platform-gujo-core/graphify-out/graph.json"
    ) as NSString).expandingTildeInPath

    /// 1순위 공용 키. 레거시 감사기 키는 하위 호환으로 뒤에 둔다.
    public static let defaultGraphArtifactEnvironmentKeys: [String] = [
        "LARAVEL_KNOWLEDGE_PIPELINE_GRAPH_ARTIFACT_PATH",
        "APP_FLEET_QUALITY_AUDITOR_GRAPH_ARTIFACT_PATH",
    ]

    public let graphifyMirrorURL: URL
    public let architectureMirrorURL: URL
    public let wikiMirrorURL: URL
    public let graphArtifactURL: URL
    public let stallInterval: TimeInterval

    public init(
        graphifyMirrorURL: URL = URL(
            fileURLWithPath: StateMirror.path(app: "KnowledgeGraphStudio")
        ),
        architectureMirrorURL: URL = URL(
            fileURLWithPath: StateMirror.path(app: "Laravel Architecture Graph")
        ),
        wikiMirrorURL: URL = URL(
            fileURLWithPath: StateMirror.path(app: "memo-citation-ledger")
        ),
        graphArtifactURL: URL? = nil,
        stallInterval: TimeInterval = 300,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        graphArtifactEnvironmentKeys: [String] = Self.defaultGraphArtifactEnvironmentKeys,
        defaultGraphArtifactPath: String? = Self.standardGraphArtifactPath
    ) {
        self.graphifyMirrorURL = graphifyMirrorURL
        self.architectureMirrorURL = architectureMirrorURL
        self.wikiMirrorURL = wikiMirrorURL
        let environmentGraphArtifactPath = graphArtifactEnvironmentKeys
            .compactMap { key in environment[key].flatMap { $0.isEmpty ? nil : $0 } }
            .first
        let resolvedPath = graphArtifactURL?.path
            ?? environmentGraphArtifactPath
            ?? defaultGraphArtifactPath
            ?? Self.standardGraphArtifactPath
        self.graphArtifactURL = URL(fileURLWithPath: resolvedPath)
        self.stallInterval = stallInterval
    }
}

/// graph 산출물 파싱 결과를 mtime·size 로 재사용하는 프로세스 전역 캐시.
///
/// 한 칸만 들고 있다 — 소비처는 경로 하나를 반복해서 본다. 경로가 바뀌면 그냥 새로 읽는다.
private final class GraphArtifactCache: @unchecked Sendable {
    struct Stamp: Equatable {
        let path: String
        let modifiedAt: Date?
        let size: Int64
    }

    static let shared = GraphArtifactCache()

    private let lock = NSLock()
    private var stamp: Stamp?
    private var inspection: GraphArtifactInspection?

    func value(for stamp: Stamp) -> GraphArtifactInspection? {
        lock.lock()
        defer { lock.unlock() }
        // mtime 이 nil 이면 신선도를 판정할 수 없다 — 캐시하지 않는다.
        guard stamp.modifiedAt != nil, self.stamp == stamp else { return nil }
        return inspection
    }

    func store(_ inspection: GraphArtifactInspection, for stamp: Stamp) {
        guard stamp.modifiedAt != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        self.stamp = stamp
        self.inspection = inspection
    }

    /// 테스트 전용 — 프로세스 전역 상태가 테스트 사이에 새지 않게.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        stamp = nil
        inspection = nil
    }
}

public struct LaravelKnowledgePipelineInspector: Sendable {
    public let configuration: LaravelKnowledgePipelineConfiguration

    public init(configuration: LaravelKnowledgePipelineConfiguration = .init()) {
        self.configuration = configuration
    }

    public func inspect(now: Date = Date()) -> LaravelKnowledgePipelineSnapshot {
        LaravelKnowledgePipelineSnapshot(
            graphify: inspectGraphify(now: now),
            architecture: inspectArchitecture(),
            wiki: inspectWiki()
        )
    }

    private func inspectGraphify(now: Date) -> PipelineSourceSnapshot {
        let artifact = inspectGraphArtifact()

        do {
            let envelope = try StateMirror.read(
                url: configuration.graphifyMirrorURL,
                as: GraphifyMirrorState.self
            )
            return graphifySnapshot(envelope: envelope, artifact: artifact, now: now)
        } catch let error as StateMirrorReadError {
            switch error {
            case .missing:
                if case .valid(let facts, let modifiedAt) = artifact {
                    return PipelineSourceSnapshot(
                        id: "graphify",
                        title: "Graphify",
                        health: .healthy,
                        summary: "graph artifact healthy; app unavailable",
                        detail: configuration.graphArtifactURL.path,
                        updatedAt: modifiedAt,
                        facts: facts
                    )
                }
                if case .malformed(let detail) = artifact {
                    return warning(
                        id: "graphify",
                        title: "Graphify",
                        summary: "graph artifact malformed; app unavailable",
                        detail: detail
                    )
                }
                return .unavailable(id: "graphify", title: "Graphify")
            case .malformed(let detail):
                return warning(
                    id: "graphify",
                    title: "Graphify",
                    summary: "app state malformed",
                    detail: detail,
                    facts: artifact.facts
                )
            }
        } catch {
            return warning(
                id: "graphify",
                title: "Graphify",
                summary: "app state unavailable",
                detail: error.localizedDescription,
                facts: artifact.facts
            )
        }
    }

    private func graphifySnapshot(
        envelope: StateMirrorEnvelope<GraphifyMirrorState>,
        artifact: GraphArtifactInspection,
        now: Date
    ) -> PipelineSourceSnapshot {
        let state = envelope.state
        let operation = state.operationState
        var facts = state.facts
        facts.merge(artifact.facts) { _, artifactValue in artifactValue }

        let health: PipelineHealth
        if operation?.status == .running,
           let updated = Self.date(from: envelope.updatedAt),
           now.timeIntervalSince(updated) > configuration.stallInterval {
            health = .stalled
        } else if operation?.status == .failed {
            health = .failed
        } else if operation?.status == .running {
            health = .running
        } else {
            switch artifact {
            case .valid:
                health = .healthy
            case .malformed:
                health = .warning
            case .missing:
                health = .unavailable
            }
        }

        let summary: String
        switch health {
        case .running:
            summary = operation?.phase ?? operation?.operation ?? "running"
        case .stalled:
            summary = "stalled: \(operation?.phase ?? operation?.operation ?? "running")"
        case .failed:
            summary = operation?.message ?? operation?.error ?? "failed"
        case .warning:
            summary = "graph artifact malformed"
        case .unavailable:
            summary = "graph artifact unavailable"
        default:
            summary = operation?.message ?? "healthy"
        }

        let artifactError: String?
        if case .malformed(let detail) = artifact {
            artifactError = detail
        } else {
            artifactError = nil
        }

        return PipelineSourceSnapshot(
            id: "graphify",
            title: "Graphify",
            health: health,
            summary: summary,
            detail: operation?.error ?? artifactError,
            progress: .init(
                completed: operation?.completed,
                total: operation?.total,
                unit: operation?.unit,
                currentTarget: operation?.currentTarget ?? state.target
            ),
            updatedAt: envelope.updatedAt,
            facts: facts
        )
    }

    private func inspectArchitecture() -> PipelineSourceSnapshot {
        do {
            let envelope = try StateMirror.read(
                url: configuration.architectureMirrorURL,
                as: ArchitectureMirrorState.self
            )
            let state = envelope.state
            let summary = state.scanning
                ? "scanning \(state.selectedApp ?? state.appsDir ?? "Laravel apps")"
                : state.selectedApp.map { "selected \($0)" } ?? "scan ready"
            return PipelineSourceSnapshot(
                id: "laravel-architecture",
                title: "Laravel architecture",
                health: state.scanning ? .running : .healthy,
                summary: summary,
                detail: nil,
                progress: .init(currentTarget: state.selectedApp),
                updatedAt: envelope.updatedAt,
                facts: state.facts
            )
        } catch let error as StateMirrorReadError {
            switch error {
            case .missing:
                return .unavailable(
                    id: "laravel-architecture",
                    title: "Laravel architecture"
                )
            case .malformed(let detail):
                return warning(
                    id: "laravel-architecture",
                    title: "Laravel architecture",
                    summary: "app state malformed",
                    detail: detail
                )
            }
        } catch {
            return warning(
                id: "laravel-architecture",
                title: "Laravel architecture",
                summary: "app state unavailable",
                detail: error.localizedDescription
            )
        }
    }

    private func inspectWiki() -> PipelineSourceSnapshot {
        do {
            let envelope = try StateMirror.read(
                url: configuration.wikiMirrorURL,
                as: WikiMirrorState.self
            )
            let state = envelope.state
            let hasWarning = state.integrityProblems > 0 || state.cliStale
            let summary: String
            if state.integrityProblems > 0 && state.cliStale {
                summary = "\(state.integrityProblems) integrity problems; CLI version drift"
            } else if state.integrityProblems > 0 {
                summary = "\(state.integrityProblems) integrity problems"
            } else if state.cliStale {
                summary = "CLI version drift"
            } else {
                summary = "ledger healthy"
            }
            return PipelineSourceSnapshot(
                id: "gujo-wiki",
                title: "gujo wiki",
                health: hasWarning ? .warning : .healthy,
                summary: summary,
                detail: state.root,
                progress: .init(currentTarget: state.root),
                updatedAt: envelope.updatedAt,
                facts: state.facts
            )
        } catch let error as StateMirrorReadError {
            switch error {
            case .missing:
                return .unavailable(id: "gujo-wiki", title: "gujo wiki")
            case .malformed(let detail):
                return warning(
                    id: "gujo-wiki",
                    title: "gujo wiki",
                    summary: "app state malformed",
                    detail: detail
                )
            }
        } catch {
            return warning(
                id: "gujo-wiki",
                title: "gujo wiki",
                summary: "app state unavailable",
                detail: error.localizedDescription
            )
        }
    }

    /// 산출물은 **바뀌었을 때만** 다시 읽는다.
    ///
    /// 이 아티팩트는 실측 12MB다. 소비처가 폴링(감사기 GUI 는 2초)하면 매 tick 마다
    /// 12MB read + JSONSerialization 이 돌고, 그게 메인 스레드면 앱이 사실상 계속
    /// 멈춰 있다 — 실측으로 AX 조회가 -25204(timeout)로 죽었고 3초 샘플의 100%가
    /// 이 함수의 `open()` 안이었다. mtime·size 가 같으면 파싱 결과를 그대로 돌려준다.
    private func inspectGraphArtifact() -> GraphArtifactInspection {
        let path = configuration.graphArtifactURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return .missing
        }
        let stamp = GraphArtifactCache.Stamp(
            path: path,
            modifiedAt: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? -1
        )
        if let cached = GraphArtifactCache.shared.value(for: stamp) { return cached }
        let inspection = parseGraphArtifact(modifiedAt: stamp.modifiedAt)
        GraphArtifactCache.shared.store(inspection, for: stamp)
        return inspection
    }

    private func parseGraphArtifact(modifiedAt: Date?) -> GraphArtifactInspection {
        do {
            let data = try Data(contentsOf: configuration.graphArtifactURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GraphArtifactError.invalidRoot
            }
            let nodes = (object["nodes"] as? [Any])?.count ?? 0
            let links = (object["links"] as? [Any])?.count ?? 0
            let communities = Set(
                (object["nodes"] as? [[String: Any]])?
                    .compactMap { $0["community"] as? Int } ?? []
            ).count
            var facts = [
                "nodes": String(nodes),
                "links": String(links),
                "communities": String(communities),
            ]
            if let modifiedAt {
                facts["artifactModifiedAt"] = Self.string(from: modifiedAt)
            }
            return .valid(facts: facts, modifiedAt: modifiedAt.map(Self.string(from:)))
        } catch {
            return .malformed(
                "\(configuration.graphArtifactURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func warning(
        id: String,
        title: String,
        summary: String,
        detail: String?,
        facts: [String: String] = [:]
    ) -> PipelineSourceSnapshot {
        PipelineSourceSnapshot(
            id: id,
            title: title,
            health: .warning,
            summary: summary,
            detail: detail,
            updatedAt: nil,
            facts: facts
        )
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private enum GraphArtifactInspection {
    case missing
    case malformed(String)
    case valid(facts: [String: String], modifiedAt: String?)

    var facts: [String: String] {
        if case .valid(let facts, _) = self {
            return facts
        }
        return [:]
    }
}

private enum GraphArtifactError: LocalizedError {
    case invalidRoot

    var errorDescription: String? {
        "expected a JSON object"
    }
}

private struct GraphifyMirrorState: Decodable, Sendable {
    let target: String?
    let targets: Int?
    let hasGraph: Bool?
    let nodes: Int?
    let links: Int?
    let communities: Int?
    let backend: String?
    let serving: Bool?
    let watching: Bool?
    let cliVersion: String?
    let operationState: LongRunningOperationState?

    var facts: [String: String] {
        var facts: [String: String] = [:]
        facts.set("targets", targets)
        facts.set("hasGraph", hasGraph)
        facts.set("nodes", nodes)
        facts.set("links", links)
        facts.set("communities", communities)
        facts.set("backend", backend)
        facts.set("serving", serving)
        facts.set("watching", watching)
        facts.set("cliVersion", cliVersion)
        return facts
    }
}

private struct ArchitectureMirrorState: Decodable, Sendable {
    struct Graph: Decodable, Sendable {
        let models: Int?
        let modelEdges: Int?
        let modules: Int?
        let couplingEdges: Int?
        let renders: Int?
        let pages: Int?
        let findings: Int?
    }

    let appsDir: String?
    let scannedApps: Int?
    let selectedApp: String?
    let scanning: Bool
    let wiring: Int?
    let arch: Int?
    let e2e: Int?
    let graph: Graph?

    var facts: [String: String] {
        var facts: [String: String] = [:]
        facts.set("scannedApps", scannedApps)
        facts.set("wiring", wiring)
        facts.set("arch", arch)
        facts.set("e2e", e2e)
        facts.set("models", graph?.models)
        facts.set("modelEdges", graph?.modelEdges)
        facts.set("modules", graph?.modules)
        facts.set("couplingEdges", graph?.couplingEdges)
        facts.set("renders", graph?.renders)
        facts.set("pages", graph?.pages)
        facts.set("findings", graph?.findings)
        return facts
    }
}

private struct WikiMirrorState: Decodable, Sendable {
    let root: String?
    let area: String?
    let selectedDocumentID: String?
    let documentCount: Int
    let objectCount: Int
    let integrityProblems: Int
    let cliStale: Bool
    let cliInstalledVersion: String?
    let cliExpectedVersion: String?

    var facts: [String: String] {
        var facts: [String: String] = [
            "documentCount": String(documentCount),
            "objectCount": String(objectCount),
            "integrityProblems": String(integrityProblems),
            "cliStale": String(cliStale),
        ]
        facts.set("area", area)
        facts.set("cliInstalledVersion", cliInstalledVersion)
        facts.set("cliExpectedVersion", cliExpectedVersion)
        return facts
    }
}

private extension Dictionary where Key == String, Value == String {
    mutating func set<T>(_ key: String, _ value: T?) {
        guard let value else { return }
        self[key] = String(describing: value)
    }
}
