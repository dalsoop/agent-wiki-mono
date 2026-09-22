import Foundation
import LaravelKnowledgePipelineKit
import StateMirrorKit
import XCTest

final class LaravelKnowledgePipelineTests: XCTestCase {
    private var fixture: LaravelPipelineFixture!
    private var configuration: LaravelKnowledgePipelineConfiguration {
        fixture.configuration
    }
    private var inspector: LaravelKnowledgePipelineInspector {
        LaravelKnowledgePipelineInspector(configuration: configuration)
    }

    override func setUpWithError() throws {
        fixture = try LaravelPipelineFixture()
    }

    override func tearDownWithError() throws {
        fixture.remove()
        fixture = nil
    }

    func testEnvironmentOverrideSelectsIsolatedGraphArtifact() {
        let configuration = LaravelKnowledgePipelineConfiguration(
            environment: [
                "LARAVEL_KNOWLEDGE_PIPELINE_GRAPH_ARTIFACT_PATH":
                    "/tmp/isolated-target/graphify-out/graph.json"
            ]
        )

        XCTAssertEqual(
            configuration.graphArtifactURL.path,
            "/tmp/isolated-target/graphify-out/graph.json"
        )
    }

    func testLegacyAuditorEnvironmentKeyStillWorks() {
        let configuration = LaravelKnowledgePipelineConfiguration(
            environment: [
                "APP_FLEET_QUALITY_AUDITOR_GRAPH_ARTIFACT_PATH":
                    "/tmp/legacy-auditor/graphify-out/graph.json"
            ]
        )

        XCTAssertEqual(
            configuration.graphArtifactURL.path,
            "/tmp/legacy-auditor/graphify-out/graph.json"
        )
    }

    func testExplicitGraphArtifactURLBeatsEnvironment() {
        let configuration = LaravelKnowledgePipelineConfiguration(
            graphArtifactURL: URL(fileURLWithPath: "/tmp/explicit/graph.json"),
            environment: [
                "LARAVEL_KNOWLEDGE_PIPELINE_GRAPH_ARTIFACT_PATH":
                    "/tmp/env/graph.json"
            ]
        )

        XCTAssertEqual(configuration.graphArtifactURL.path, "/tmp/explicit/graph.json")
    }

    func testDefaultGraphArtifactPathInjection() {
        let configuration = LaravelKnowledgePipelineConfiguration(
            environment: [:],
            defaultGraphArtifactPath: "/tmp/custom-default/graph.json"
        )

        XCTAssertEqual(
            configuration.graphArtifactURL.path,
            "/tmp/custom-default/graph.json"
        )
    }

    func testRunningGraphifyUsesPublishedRealProgress() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: .init(
                status: .running,
                operation: "graphify-update",
                phase: "extracting",
                completed: 200,
                total: 513,
                unit: "files",
                currentTarget: "/laravel/platform-gujo-core"
            )
        )

        let snapshot = inspector.inspect(now: iso("2026-07-23T00:10:00Z"))

        XCTAssertEqual(snapshot.graphify.health, .running)
        XCTAssertEqual(snapshot.graphify.completed, 200)
        XCTAssertEqual(snapshot.graphify.total, 513)
        XCTAssertEqual(snapshot.graphify.unit, "files")
        XCTAssertEqual(snapshot.graphify.currentTarget, "/laravel/platform-gujo-core")
    }

    func testRunningGraphifyOlderThanFiveMinutesIsStalled() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:04:59Z",
            operation: fixture.runningOperation
        )

        XCTAssertEqual(
            inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify.health,
            .stalled
        )
    }

    func testRunningGraphifyExactlyFiveMinutesOldIsStillRunning() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:05:00Z",
            operation: fixture.runningOperation
        )

        XCTAssertEqual(
            inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify.health,
            .running
        )
    }

    func testFailedGraphifyTakesPrecedenceOverValidArtifact() throws {
        try fixture.writeGraph(nodes: 2, links: 1)
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: .init(
                status: .failed,
                operation: "graphify-update",
                phase: "extracting",
                report: .init(
                    message: "command exited 1",
                    error: "exit 1"
                )
            )
        )

        let graphify = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify

        XCTAssertEqual(graphify.health, .failed)
        XCTAssertEqual(graphify.detail, "exit 1")
        XCTAssertEqual(graphify.facts["nodes"], "2")
    }

    func testMissingGraphifyMirrorStillReportsHealthyArtifact() throws {
        try fixture.writeGraph(nodes: 2, links: 1)

        let graphify = inspector.inspect(now: Date()).graphify

        XCTAssertEqual(graphify.health, .healthy)
        XCTAssertEqual(graphify.facts["nodes"], "2")
        XCTAssertEqual(graphify.facts["links"], "1")
        XCTAssertEqual(graphify.facts["communities"], "2")
        XCTAssertTrue(graphify.summary.contains("app unavailable"))
    }

    func testMissingArtifactMakesIdleGraphifyUnavailable() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: .idle
        )

        let graphify = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify

        XCTAssertEqual(graphify.health, .unavailable)
    }

    func testMissingArtifactMakesSucceededGraphifyUnavailable() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: .init(status: .succeeded, operation: "graphify-update")
        )

        let graphify = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify

        XCTAssertEqual(graphify.health, .unavailable)
    }

    func testMissingArtifactMakesGraphifyWithoutOperationUnavailable() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: nil
        )

        let graphify = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify

        XCTAssertEqual(graphify.health, .unavailable)
    }

    /// 12MB 산출물을 2초마다 다시 파싱해 메인 스레드를 막던 것을 막는다(2026-08-05).
    /// mtime·size 가 그대로면 **파일을 다시 읽지 않는다** — 내용을 몰래 바꿔도 옛 수치가 나온다.
    func testGraphArtifactIsNotRereadWhileMtimeAndSizeAreUnchanged() throws {
        // mtime 은 양쪽 다 setAttributes 로 **같은 값을 심는다** — 읽은 Date 를 되돌려
        // 심으면 소수점이 깎여 stamp 가 어긋난다(파일시스템 왕복 정밀도 함정).
        let pinned = Date(timeIntervalSince1970: 1_760_000_000)
        let path = configuration.graphArtifactURL.path
        try fixture.writeGraph(nodes: 4, links: 3)
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        try FileManager.default.setAttributes([.modificationDate: pinned], ofItemAtPath: path)

        let first = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify
        XCTAssertEqual(first.facts["nodes"], "4")

        // 같은 크기·같은 mtime 으로 덮어쓴다 — 다시 읽었다면 JSON 이 깨져 nil 이 나온다.
        try Data(repeating: 0x20, count: size?.intValue ?? 0).write(to: configuration.graphArtifactURL)
        try FileManager.default.setAttributes([.modificationDate: pinned], ofItemAtPath: path)

        let second = inspector.inspect(now: iso("2026-07-23T00:10:02Z")).graphify
        XCTAssertEqual(second.facts["nodes"], "4", "캐시가 안 먹어 공백 파일을 다시 파싱했다")
    }

    /// 캐시가 눌러앉으면 안 된다 — 산출물이 갱신되면 다음 tick 에 반영돼야 한다.
    func testGraphArtifactIsRereadAfterItChanges() throws {
        try fixture.writeGraph(nodes: 4, links: 3)
        XCTAssertEqual(
            inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify.facts["nodes"], "4")

        try fixture.writeGraph(nodes: 9, links: 8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: configuration.graphArtifactURL.path
        )

        XCTAssertEqual(
            inspector.inspect(now: iso("2026-07-23T00:10:02Z")).graphify.facts["nodes"], "9")
    }

    func testMalformedArtifactWarnsEvenWhenGraphifyMirrorIsValid() throws {
        try fixture.writeGraphifyMirror(
            updatedAt: "2026-07-23T00:09:30Z",
            operation: .init(status: .succeeded, operation: "graphify-update")
        )
        try "{bad".write(
            to: configuration.graphArtifactURL,
            atomically: true,
            encoding: .utf8
        )

        let graphify = inspector.inspect(now: iso("2026-07-23T00:10:00Z")).graphify

        XCTAssertEqual(graphify.health, .warning)
        XCTAssertTrue(graphify.detail?.contains(configuration.graphArtifactURL.path) == true)
    }

    func testWikiIntegrityAndVersionDriftAreWarnings() throws {
        try fixture.writeWikiMirror(integrityProblems: 2, cliStale: true)

        let wiki = inspector.inspect(now: Date()).wiki

        XCTAssertEqual(wiki.health, .warning)
        XCTAssertEqual(wiki.facts["integrityProblems"], "2")
        XCTAssertEqual(wiki.facts["cliStale"], "true")
    }

    func testMalformedSourceIsIsolatedFromOtherSources() throws {
        try "{bad".write(
            to: configuration.graphifyMirrorURL,
            atomically: true,
            encoding: .utf8
        )
        try fixture.writeArchitectureMirror()
        try fixture.writeWikiMirror(integrityProblems: 0, cliStale: false)

        let snapshot = inspector.inspect(now: Date())

        XCTAssertEqual(snapshot.graphify.health, .warning)
        XCTAssertEqual(snapshot.architecture.health, .healthy)
        XCTAssertEqual(snapshot.wiki.health, .healthy)
    }

    func testProgressTextRequiresBothRealCounts() {
        let determinate = source(
            completed: 200,
            total: 513,
            unit: "files"
        )
        let indeterminate = source(
            completed: nil,
            total: nil,
            unit: nil
        )

        XCTAssertEqual(determinate.progressText, "200/513 files")
        XCTAssertNil(indeterminate.progressText)
    }

    private func source(
        completed: Int?,
        total: Int?,
        unit: String?
    ) -> PipelineSourceSnapshot {
        PipelineSourceSnapshot(
            id: "graphify",
            title: "Graphify",
            health: .running,
            summary: "extracting",
            detail: nil,
            progress: .init(completed: completed, total: total, unit: unit, currentTarget: "/repo"),
            updatedAt: "2026-07-23T00:00:00Z",
            facts: [:]
        )
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class LaravelPipelineFixture {
    let root: URL
    let configuration: LaravelKnowledgePipelineConfiguration

    let runningOperation = LongRunningOperationState(
        status: .running,
        operation: "graphify-update",
        phase: "extracting",
        completed: 10,
        total: 20,
        unit: "files",
        currentTarget: "/laravel/platform-gujo-core"
    )

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laravel-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configuration = LaravelKnowledgePipelineConfiguration(
            graphifyMirrorURL: root.appendingPathComponent("graphify.json"),
            architectureMirrorURL: root.appendingPathComponent("architecture.json"),
            wikiMirrorURL: root.appendingPathComponent("wiki.json"),
            graphArtifactURL: root.appendingPathComponent("graph.json"),
            stallInterval: 300
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeGraphifyMirror(
        updatedAt: String,
        operation: LongRunningOperationState?
    ) throws {
        try writeMirror(
            app: "KnowledgeGraphStudio",
            updatedAt: updatedAt,
            state: GraphifyStateFixture(
                target: "/laravel/platform-gujo-core",
                nodes: 9,
                links: 8,
                communities: 7,
                operationState: operation
            ),
            to: configuration.graphifyMirrorURL
        )
    }

    func writeArchitectureMirror() throws {
        try writeMirror(
            app: "Laravel Architecture Graph",
            updatedAt: "2026-07-23T00:09:30Z",
            state: ArchitectureStateFixture(
                appsDir: "/laravel/apps",
                scannedApps: 5,
                selectedApp: "platform-gujo-core",
                scanning: false,
                wiring: 100,
                arch: 40,
                e2e: 8,
                graph: .init(
                    models: 19,
                    modelEdges: 46,
                    modules: 11,
                    couplingEdges: 20,
                    renders: 2,
                    pages: 2,
                    findings: 0
                )
            ),
            to: configuration.architectureMirrorURL
        )
    }

    func writeWikiMirror(integrityProblems: Int, cliStale: Bool) throws {
        try writeMirror(
            app: "memo-citation-ledger",
            updatedAt: "2026-07-23T00:09:30Z",
            state: WikiStateFixture(
                root: "/gujo-wiki",
                documentCount: 1_050,
                objectCount: 1_404,
                integrityProblems: integrityProblems,
                cliStale: cliStale,
                cliInstalledVersion: cliStale ? "old" : nil,
                cliExpectedVersion: "current"
            ),
            to: configuration.wikiMirrorURL
        )
    }

    func writeGraph(nodes: Int, links: Int) throws {
        let graphNodes = (0..<nodes).map {
            ["id": "node-\($0)", "community": $0 % 2] as [String: Any]
        }
        let graphLinks = (0..<links).map {
            ["source": "node-\($0)", "target": "node-\($0 + 1)"]
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["nodes": graphNodes, "links": graphLinks],
            options: [.sortedKeys]
        )
        try data.write(to: configuration.graphArtifactURL)
    }

    private func writeMirror<State: Encodable>(
        app: String,
        updatedAt: String,
        state: State,
        to url: URL
    ) throws {
        let envelope = MirrorFixture(app: app, updatedAt: updatedAt, state: state)
        try JSONEncoder().encode(envelope).write(to: url)
    }
}

private struct MirrorFixture<State: Encodable>: Encodable {
    let app: String
    let updatedAt: String
    let state: State
}

private struct GraphifyStateFixture: Encodable {
    let target: String
    let nodes: Int
    let links: Int
    let communities: Int
    let operationState: LongRunningOperationState?
}

private struct ArchitectureStateFixture: Encodable {
    struct Graph: Encodable {
        let models: Int
        let modelEdges: Int
        let modules: Int
        let couplingEdges: Int
        let renders: Int
        let pages: Int
        let findings: Int
    }

    let appsDir: String
    let scannedApps: Int
    let selectedApp: String
    let scanning: Bool
    let wiring: Int
    let arch: Int
    let e2e: Int
    let graph: Graph
}

private struct WikiStateFixture: Encodable {
    let root: String
    let documentCount: Int
    let objectCount: Int
    let integrityProblems: Int
    let cliStale: Bool
    let cliInstalledVersion: String?
    let cliExpectedVersion: String
}
