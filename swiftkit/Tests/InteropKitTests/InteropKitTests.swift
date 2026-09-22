import XCTest
@testable import InteropKit

final class EnvelopeTests: XCTestCase {
    struct Payload: Codable, Equatable {
        let count: Int
        let label: String
    }

    func testCodableRoundTripSuccess() throws {
        let data = try Envelope.ok(Payload(count: 3, label: "jobs"))
        let decoded = try Envelope.decodeResult(Payload.self, from: data)
        XCTAssertEqual(decoded, Payload(count: 3, label: "jobs"))
        // 계약 봉투 키 확인.
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertNotNil(object["result"])
    }

    func testCodableFailureBecomesError() throws {
        let data = try Envelope.fail("boom")
        XCTAssertThrowsError(try Envelope.decodeResult(Payload.self, from: data)) { error in
            XCTAssertEqual(error as? EnvelopeError, .remote(message: "boom"))
        }
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertEqual((object["error"] as? [String: Any])?["message"] as? String, "boom")
    }

    func testObjectRoundTrip() throws {
        let data = try Envelope.okObject(["a": 1])
        let result = try XCTUnwrap(try Envelope.parseObject(data) as? [String: Any])
        XCTAssertEqual(result["a"] as? Int, 1)

        let failData = try Envelope.failObject("nope")
        XCTAssertThrowsError(try Envelope.parseObject(failData)) { error in
            XCTAssertEqual(error as? EnvelopeError, .remote(message: "nope"))
        }
    }

    func testMalformedEnvelope() {
        let data = Data("{\"nope\": 1}".utf8)
        XCTAssertThrowsError(try Envelope.parseObject(data)) { error in
            XCTAssertEqual(error as? EnvelopeError, .malformed)
        }
    }
}

final class CapabilitiesTests: XCTestCase {
    // docs/app-interop-contract.md 의 JSON 예시 그대로 — 정본과 1:1 임을 고정.
    let contractExample = """
    {
      "ok": true,
      "result": {
        "name": "hermes",
        "version": "1.4.0",
        "cli": "/Users/x/.local/bin/hermes",
        "commands": [
          {"name": "jobs", "summary": "등록된 잡 목록", "json": true},
          {"name": "runs", "summary": "실행 이력", "json": true}
        ],
        "state": [
          {"path": "~/.config/hermes/jobs.json", "what": "잡 정의"},
          {"path": "~/.config/hermes/runs.jsonl", "what": "실행 이력"}
        ],
        "health": {"command": "hermes jobs --json", "freshness": "~/.config/hermes/runs.jsonl"}
      }
    }
    """

    func testDecodesContractExample() throws {
        let capabilities = try Envelope.decodeResult(
            Capabilities.self, from: Data(contractExample.utf8)
        )
        XCTAssertEqual(capabilities.name, "hermes")
        XCTAssertEqual(capabilities.version, "1.4.0")
        XCTAssertEqual(capabilities.cli, "/Users/x/.local/bin/hermes")
        XCTAssertEqual(capabilities.commands.count, 2)
        XCTAssertEqual(capabilities.commands[0].name, "jobs")
        XCTAssertEqual(capabilities.commands[0].summary, "등록된 잡 목록")
        XCTAssertTrue(capabilities.commands[0].json)
        XCTAssertEqual(capabilities.state.count, 2)
        XCTAssertEqual(capabilities.state[1].path, "~/.config/hermes/runs.jsonl")
        XCTAssertEqual(capabilities.state[1].what, "실행 이력")
        XCTAssertEqual(capabilities.health.command, "hermes jobs --json")
        XCTAssertEqual(capabilities.health.freshness, "~/.config/hermes/runs.jsonl")
    }

    func testRoundTrip() throws {
        let capabilities = try Envelope.decodeResult(
            Capabilities.self, from: Data(contractExample.utf8)
        )
        let reencoded = try Envelope.ok(capabilities)
        let decoded = try Envelope.decodeResult(Capabilities.self, from: reencoded)
        XCTAssertEqual(decoded, capabilities)
    }

    func testTildeExpansion() {
        let expanded = Capabilities.expandingTilde("~/.config/hermes/jobs.json")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/.config/hermes/jobs.json"))
        // 절대 경로는 그대로 둔다.
        XCTAssertEqual(Capabilities.expandingTilde("/tmp/x"), "/tmp/x")
    }

    func testProceduresDefaultEmptyAndRoundTrip() throws {
        let capabilities = try Envelope.decodeResult(
            Capabilities.self, from: Data(contractExample.utf8)
        )
        XCTAssertEqual(capabilities.procedures, [])
        let withProc = Capabilities(
            name: "gpu-server-manager",
            version: "1.0.0",
            cli: HostPlatform.cliBinPath("gpu-server-manager"),
            commands: [],
            state: [],
            health: .init(command: "x", freshness: ""),
            owned: .init(procedures: [
                Procedure(
                    id: "gpu.60.bring-up",
                    title: "60 GPU 켜기",
                    summary: "카드부터 점검까지",
                    owner: "gpu-server-manager",
                    steps: [
                        .init(id: "cards", title: "카드", app: "gpu-server-manager", argv: ["gpus", "--site", "60"]),
                    ]
                )
            ])
        )
        XCTAssertEqual(withProc.normalizedForRegistry().procedures.count, 1)
        XCTAssertEqual(withProc.normalizedForRegistry().procedures[0].steps[0].commandLine, "gpu-server-manager gpus --site 60")
        let data = try JSONEncoder().encode(withProc)
        let decoded = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(decoded.procedures, withProc.procedures)
    }

    /// depends 없는 기존 JSON 은 빈 배열로 decode 한다(하위호환).
    func testDependsDefaultsToEmptyWhenOmitted() throws {
        let capabilities = try Envelope.decodeResult(
            Capabilities.self, from: Data(contractExample.utf8)
        )
        XCTAssertEqual(capabilities.depends, [])
    }

    func testDependsRoundTrip() throws {
        let withDepends = """
        {
          "ok": true,
          "result": {
            "name": "dns-switcher",
            "version": "1.0.0",
            "cli": "\(HostPlatform.cliBinPath("dns-switcher"))",
            "commands": [{"name": "capabilities", "summary": "자기소개", "json": true}],
            "state": [],
            "health": {"command": "dns-switcher capabilities", "freshness": ""},
            "depends": [
              {
                "id": "system.networksetup",
                "kind": "command",
                "ref": "networksetup",
                "required": true,
                "why": "DNS/인터페이스 적용"
              },
              {
                "id": "cli.agent-approval",
                "kind": "cli",
                "ref": "agent-approval",
                "required": true,
                "why": "승인 게이트",
                "commands": ["show"]
              }
            ]
          }
        }
        """
        let capabilities = try Envelope.decodeResult(
            Capabilities.self, from: Data(withDepends.utf8)
        )
        XCTAssertEqual(capabilities.depends.count, 2)
        XCTAssertEqual(capabilities.depends[0].id, "system.networksetup")
        XCTAssertEqual(capabilities.depends[0].kind, Capabilities.DependencyKind.command)
        XCTAssertEqual(capabilities.depends[0].ref, "networksetup")
        XCTAssertTrue(capabilities.depends[0].required)
        XCTAssertEqual(capabilities.depends[1].commands, ["show"])

        let reencoded = try Envelope.ok(capabilities)
        let decoded = try Envelope.decodeResult(Capabilities.self, from: reencoded)
        XCTAssertEqual(decoded, capabilities)
    }

    /// 알 수 없는 kind 문자열도 decode 실패하지 않는다(전방호환).
    func testUnknownDependencyKindPreserved() throws {
        let json = """
        {
          "ok": true,
          "result": {
            "name": "x",
            "version": "1",
            "cli": "\(HostPlatform.cliBinPath("x"))",
            "commands": [],
            "state": [],
            "health": {"command": "x capabilities", "freshness": ""},
            "depends": [
              {"id": "future.thing", "kind": "future.kind", "ref": "thing", "required": false, "why": "전방호환"}
            ]
          }
        }
        """
        let caps = try Envelope.decodeResult(Capabilities.self, from: Data(json.utf8))
        XCTAssertEqual(caps.depends.first?.kind, "future.kind")
    }
}

final class RegistryTests: XCTestCase {
    var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteropKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeCapabilities(name: String, version: String = "1.0.0") -> Capabilities {
        Capabilities(
            name: name,
            version: version,
            cli: "/usr/local/bin/\(name)",
            commands: [.init(name: "status", summary: "상태", json: true)],
            state: [.init(path: "~/.config/\(name)/state.json", what: "상태")],
            health: .init(
                command: "\(name) status --json",
                freshness: "~/.config/\(name)/state.json"
            )
        )
    }

    func testLoadMissingFileReturnsEmpty() throws {
        let store = RegistryStore(fileURL: tempDir.appendingPathComponent("apps.json"))
        let registry = try store.load()
        XCTAssertTrue(registry.apps.isEmpty)
    }

    func testUpsertCreatesDirectoryAndReloads() throws {
        // 디렉토리가 없는 상태에서 시작 — upsert 가 만들어야 한다.
        let store = RegistryStore(
            fileURL: tempDir.appendingPathComponent(".agent-apps/apps.json")
        )
        try store.upsert(makeCapabilities(name: "hermes"))
        try store.upsert(makeCapabilities(name: "flowlog"))

        let reloaded = try store.load()
        XCTAssertEqual(Set(reloaded.apps.keys), ["hermes", "flowlog"])
        XCTAssertFalse(reloaded.updatedAt.isEmpty)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: reloaded.updatedAt))
    }

    func testUpsertReplacesExistingApp() throws {
        let store = RegistryStore(fileURL: tempDir.appendingPathComponent("apps.json"))
        try store.upsert(makeCapabilities(name: "hermes", version: "1.0.0"))
        try store.upsert(makeCapabilities(name: "hermes", version: "2.0.0"))

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.apps.count, 1)
        XCTAssertEqual(reloaded.apps["hermes"]?.version, "2.0.0")
    }

    func testSavedSchemaShape() throws {
        // 스키마 {"apps": {...}, "updatedAt": "..."} — 정본과 1:1 확인.
        let store = RegistryStore(fileURL: tempDir.appendingPathComponent("apps.json"))
        try store.upsert(makeCapabilities(name: "hermes"))
        let data = try Data(contentsOf: store.fileURL)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["apps", "updatedAt"])
        let apps = try XCTUnwrap(object["apps"] as? [String: Any])
        let hermes = try XCTUnwrap(apps["hermes"] as? [String: Any])
        // `purpose`(무엇을 하는 앱인가)가 스키마에 들어왔는데 이 기대값이 안 따라와
        // main 이 빨갛게 남아 있었다(실측 2026-08-11). 스키마를 늘릴 때 이 줄이 같이
        // 늘어야 한다 — 그러라고 **정확한 집합**으로 비교한다.
        XCTAssertEqual(
            Set(hermes.keys),
            [
                "name", "purpose", "version", "cli", "commands", "state", "health", "depends",
                "documents", "procedures", "exchanges", "bundleId",
            ]
        )
        let health = try XCTUnwrap(hermes["health"] as? [String: Any])
        let cmd = try XCTUnwrap(health["command"] as? String)
        XCTAssertTrue(cmd.hasSuffix(" capabilities"), cmd)
        XCTAssertTrue(cmd.hasPrefix("/"), cmd)
    }

    func testLoadSkipsLegacyEntryWithoutBreakingTypedRegistry() throws {
        let fileURL = tempDir.appendingPathComponent("apps.json")
        let legacy: [String: Any] = [
            "apps": [
                "pim-calendar": [
                    "name": "pim-calendar",
                    "version": "1.0.0",
                    "commands": ["health", "capabilities"],
                    "runStates": ["queued", "running"],
                ],
            ],
            "updatedAt": "2026-07-21T04:08:23Z",
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: fileURL)

        let registry = try RegistryStore(fileURL: fileURL).load()

        XCTAssertTrue(registry.apps.isEmpty)
        XCTAssertEqual(registry.updatedAt, "2026-07-21T04:08:23Z")
    }

    func testUpsertPreservesLegacyEntryRawJSON() throws {
        let fileURL = tempDir.appendingPathComponent("apps.json")
        let legacyApp: [String: Any] = [
            "name": "pim-calendar",
            "version": "1.0.0",
            "commands": ["health", "capabilities"],
            "runStates": ["queued", "running"],
        ]
        let root: [String: Any] = [
            "apps": ["pim-calendar": legacyApp],
            "updatedAt": "2026-07-21T04:08:23Z",
        ]
        try JSONSerialization.data(withJSONObject: root).write(to: fileURL)
        let store = RegistryStore(fileURL: fileURL)

        let registry = try store.upsert(makeCapabilities(name: "agent-approval"))

        XCTAssertEqual(Set(registry.apps.keys), ["agent-approval"])
        let savedData = try Data(contentsOf: fileURL)
        let savedRoot = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        )
        let savedApps = try XCTUnwrap(savedRoot["apps"] as? [String: Any])
        let savedLegacy = try XCTUnwrap(savedApps["pim-calendar"] as? [String: Any])
        XCTAssertEqual(savedLegacy["runStates"] as? [String], ["queued", "running"])
        XCTAssertNotNil(savedApps["agent-approval"])
    }

    func testNormalizedForRegistryForcesAbsoluteCapabilities() throws {
        let caps = Capabilities(
            name: "demo-app",
            version: "1",
            cli: "demo-app",
            commands: [.init(name: "version", summary: "v", json: false)],
            state: [],
            health: .init(command: "demo-app version", freshness: "")
        )
        let n = caps.normalizedForRegistry()
        XCTAssertTrue(n.cli.hasPrefix("/"), n.cli)
        XCTAssertTrue(n.cli.hasSuffix("demo-app") || n.cli.contains("demo-app"), n.cli)
        XCTAssertEqual(n.health.command, "\(n.cli) capabilities")
    }

    func testDocumentsDefaultEmptyAndSurviveNormalize() throws {
        let data = Data(#"{"name":"x","version":"1","cli":"/bin/x","commands":[],"state":[],"health":{"command":"x","freshness":""}}"#.utf8)
        let caps = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(caps.documents, [])
        let withDoc = Capabilities(
            name: "x",
            version: "1",
            cli: "/bin/x",
            commands: [],
            state: [],
            health: .init(command: "x", freshness: ""),
            owned: .init(documents: [
                .init(id: "x.s", name: "s", kind: "skill", layer: "app", trigger: "onDemand", path: "/tmp/s")
            ])
        )
        XCTAssertEqual(withDoc.normalizedForRegistry().documents.count, 1)
        XCTAssertEqual(withDoc.normalizedForRegistry().documents.first?.layer, "app")
    }

    func testRegistryUpsertRewritesHealthToCapabilities() throws {
        let fileURL = tempDir.appendingPathComponent("registry-norm.json")
        let store = RegistryStore(fileURL: fileURL)
        let caps = Capabilities(
            name: "agent-deck-like",
            version: "1",
            cli: "agent-deck-like",
            commands: [.init(name: "projects", summary: "p", json: true)],
            state: [],
            health: .init(command: "agent-deck-like projects --json", freshness: "")
        )
        _ = try store.upsert(caps)
        let loaded = try store.load()
        let got = try XCTUnwrap(loaded.apps["agent-deck-like"])
        XCTAssertTrue(got.cli.hasPrefix("/"))
        XCTAssertTrue(got.health.command.hasSuffix(" capabilities"))
        XCTAssertFalse(got.health.command.contains("projects"))
    }

}

final class DependencyProbeTests: XCTestCase {
    func testCommandPresentOnPath() {
        let probe = DependencyProbe(pathEnv: "/bin:/usr/bin")
        let report = probe.probe([
            .init(
                id: "system.ls",
                kind: Capabilities.DependencyKind.command,
                ref: "ls",
                required: true,
                why: "list"),
        ])
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.findings[0].status, "present")
    }
    func testCommandMissingFailsRequired() {
        let probe = DependencyProbe(pathEnv: "/bin")
        let report = probe.probe([
            .init(
                id: "system.nope",
                kind: Capabilities.DependencyKind.command,
                ref: "definitely-not-a-real-binary-xyz",
                required: true,
                why: "test"),
        ])
        XCTAssertFalse(report.ok)
    }
    func testOptionalMissingStillReportOk() {
        let probe = DependencyProbe(pathEnv: "/bin")
        let report = probe.probe([
            .init(
                id: "opt.nope",
                kind: Capabilities.DependencyKind.command,
                ref: "definitely-not-a-real-binary-xyz",
                required: false,
                why: "optional"),
        ])
        XCTAssertTrue(report.ok)
    }
    func testPermissionKindUnchecked() {
        let probe = DependencyProbe()
        let report = probe.probe([
            .init(
                id: "perm.a11y",
                kind: Capabilities.DependencyKind.permission,
                ref: "accessibility",
                required: true,
                why: "AX"),
        ])
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.findings[0].status, "unchecked")
    }
}

final class SparkleCDNFeedTests: XCTestCase {
    func testFeedURLMatchesPublishedObjectPath() {
        XCTAssertEqual(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.screenshotswift"),
            "https://cdn.ranode.net/apps/net/ranode/screenshotswift/appcast.xml"
        )
        XCTAssertEqual(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo", baseURL: "https://x.test/"),
            "https://x.test/apps/net/ranode/foo/appcast.xml"
        )
        XCTAssertEqual(SparkleCDNFeed.objectSlug(bundleID: "net.ranode.foo"), "net/ranode/foo")
        XCTAssertEqual(SparkleCDNFeed.bundleID(fromObjectSlug: "net/ranode/foo"), "net.ranode.foo")
    }
}
