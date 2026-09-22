import Foundation
import Testing
@testable import EndpointRouterKit

@Test("폴백 표 — 기본값은 gujo.test 서브도메인 체계를 따른다")
func fallbackDefaults() {
    let table = EndpointRouter.resolve(environment: [:], homeDirectory: "/nonexistent-home")
    #expect(table["core"] == "http://gujo.test:8001")
    #expect(table["subscription"] == nil)
    #expect(table["software"] == "http://apps.gujo.test:8012")
    #expect(table["tokens"] == "http://tokens.gujo.test:8011")
    #expect(table["core-prod"] == "https://gujo.ai")
    #expect(table["gujo-core"] == "https://gujo.ai")
    #expect(table["pay"] == "https://pay.gujo.ai")
    #expect(table["pay-prod"] == "https://pay.gujo.ai")
    #expect(table["learn"] == "https://learn.gujo.ai")
    #expect(table["learn-prod"] == "https://learn.gujo.ai")
    #expect(table["lecture"] == "http://lecture.gujo.test:8014")
    #expect(table["lecture-prod"] == "https://lecture.gujo.ai")
    #expect(table["gpu-panel"] == "")
}

@Test("GpuPanel 호환 — gpuPanel 기본값과 오버라이드를 해석한다")
func gpuPanelResolution() {
    let defaultTable = EndpointRouter.resolve(environment: [:], homeDirectory: "/nonexistent-home")
    #expect(defaultTable["gpu-panel"] == "")

    let overrideTable = EndpointRouter.resolve(
        environment: ["GUJO_ENDPOINT_GPU_PANEL": "http://10.99.99.1:8906"],
        homeDirectory: "/nonexistent-home"
    )
    #expect(overrideTable["gpu_panel"] == "http://10.99.99.1:8906")
}

@Test("임시 원장 파일 — schema_version 이 일치하면 기본값을 덮어쓴다")
func ledgerFileOverride() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let ledgerURL = dir.appendingPathComponent("endpoints.json")
    let json = """
    { "schema_version": 1,
      "endpoints": { "core": "https://example.invalid", "NEW-KEY": "https://new.invalid" },
      "note": "테스트 원장" }
    """
    try json.write(to: ledgerURL, atomically: true, encoding: .utf8)

    let table = EndpointRouter.resolve(
        environment: ["GUJO_ENDPOINTS_FILE": ledgerURL.path],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["core"] == "https://example.invalid")
    #expect(table["new-key"] == "https://new.invalid")
    #expect(table["tokens"] == "http://tokens.gujo.test:8011") // 원장에 없는 키는 폴백 유지
}

@Test("원장 파일 — 스키마 버전이 다르거나 깨졌으면 무시하고 폴백으로 내려간다")
func ledgerFileRejects() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let wrongVersion = dir.appendingPathComponent("v2.json")
    try #"{"schema_version": 99, "endpoints": {"core": "https://no.invalid"}}"#
        .write(to: wrongVersion, atomically: true, encoding: .utf8)
    #expect(EndpointRouter.loadTable(from: wrongVersion) == nil)

    let broken = dir.appendingPathComponent("broken.json")
    try "not json".write(to: broken, atomically: true, encoding: .utf8)
    #expect(EndpointRouter.loadTable(from: broken) == nil)

    let table = EndpointRouter.resolve(
        environment: ["GUJO_ENDPOINTS_FILE": wrongVersion.path],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["core"] == "http://gujo.test:8001")
}

@Test("env 개별 오버라이드 — GUJO_ENDPOINT_<KEY> 가 파일·기본값보다 우선한다")
func envIndividualOverride() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let ledgerURL = dir.appendingPathComponent("endpoints.json")
    try #"{"schema_version": 1, "endpoints": {"core": "https://file.invalid"}}"#
        .write(to: ledgerURL, atomically: true, encoding: .utf8)

    let table = EndpointRouter.resolve(
        environment: [
            "GUJO_ENDPOINTS_FILE": ledgerURL.path,
            "GUJO_ENDPOINT_CORE": "https://env.invalid",
            "GUJO_ENDPOINT_SOFTWARE": "https://software-env.invalid",
        ],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["core"] == "https://env.invalid")          // env > 파일
    #expect(table["software"] == "https://software-env.invalid") // env > 기본값
}

@Test("테넌트 경로 — StateRootKit 루트를 따라 원장 위치가 격리된다")
func tenantPathIsolation() throws {
    let tenantHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-home-\(UUID().uuidString)", isDirectory: true)
    let tenantRoot = tenantHome.appendingPathComponent(".tenants/wife", isDirectory: true)
    let ledgerDir = tenantRoot.appendingPathComponent(".app-build-manager", isDirectory: true)
    try FileManager.default.createDirectory(at: ledgerDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tenantHome) }

    // StateRootKit 가 읽는 current-context.json — 테넌트 wife 활성
    let ctxDir = tenantHome.appendingPathComponent(".agent-tenant-isolation-manager", isDirectory: true)
    try FileManager.default.createDirectory(at: ctxDir, withIntermediateDirectories: true)
    let ctx = ctxDir.appendingPathComponent("current-context.json")
    try #"{"tenantID": "tenant:wife"}"#.write(to: ctx, atomically: true, encoding: .utf8)

    let ledger = ledgerDir.appendingPathComponent("endpoints.json")
    try #"{"schema_version": 1, "endpoints": {"core": "https://wife.invalid"}}"#
        .write(to: ledger, atomically: true, encoding: .utf8)

    let resolvedURL = EndpointRouter.ledgerFileURL(environment: [:], homeDirectory: tenantHome.path)
    #expect(resolvedURL.path == ledger.path)

    let table = EndpointRouter.resolve(environment: [:], homeDirectory: tenantHome.path)
    #expect(table["core"] == "https://wife.invalid")
}

@Test("공개 표면 — all·string·url 의 키 정규화와 미등록 키 동작")
func publicSurface() {
    let table = EndpointRouter.resolve(environment: [:], homeDirectory: "/nonexistent-home")
    #expect(!table.isEmpty)
    #expect(table.count >= EndpointRouter.defaults.count)

    #expect(EndpointRouter.string("CORE") == EndpointRouter.string("core"))
    #expect(EndpointRouter.string("no-such-key") == "")
    #expect(EndpointRouter.url("core")?.host == "gujo.test")
    #expect(EndpointRouter.url("no-such-key") == nil)
}

@Test("경로 조립 — catalog·downloads 는 apps 키에 붙이고 support 는 호스트만")
func pathBuildersUseExistingKeys() {
    let table = EndpointRouter.resolve(environment: [:], homeDirectory: "/nonexistent-home")
    let apps = table["apps"] ?? ""
    let support = table["support"] ?? ""
    #expect(apps == "https://apps.gujo.ai")
    #expect(support == "https://support.gujo.ai")
    #expect(EndpointRouter.catalogPageURL(id: 30, appsBase: apps)?.absoluteString == "https://apps.gujo.ai/catalog/30")
    #expect(EndpointRouter.downloadsURL(appsBase: apps)?.absoluteString == "https://apps.gujo.ai/downloads")
    #expect(EndpointRouter.supportPageURL(supportBase: support)?.absoluteString == "https://support.gujo.ai")
    #expect((table["pay"] ?? "") == "https://pay.gujo.ai")
    #expect(EndpointRouter.joining(table["pay"] ?? "", path: "")?.absoluteString == "https://pay.gujo.ai")
    #expect(EndpointRouter.joining("", path: "catalog/1") == nil)
    #expect(EndpointRouter.joining(apps, path: "")?.absoluteString == apps)
}

@Test("learn 키 — 원장 파일이 폴백을 덮는다")
func learnLedgerOverlay() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let ledgerURL = dir.appendingPathComponent("endpoints.json")
    let json = """
    { "schema_version": 1,
      "endpoints": { "learn": "https://learn-ledger.invalid" } }
    """
    try json.write(to: ledgerURL, atomically: true, encoding: .utf8)

    let table = EndpointRouter.resolve(
        environment: ["GUJO_ENDPOINTS_FILE": ledgerURL.path],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["learn"] == "https://learn-ledger.invalid")
    #expect(table["learn-prod"] == "https://learn.gujo.ai")
}

@Test("learn 키 — GUJO_ENDPOINT_LEARN 이 원장·폴백보다 우선한다")
func learnEnvOverlay() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let ledgerURL = dir.appendingPathComponent("endpoints.json")
    try #"{"schema_version": 1, "endpoints": {"learn": "https://learn-file.invalid"}}"#
        .write(to: ledgerURL, atomically: true, encoding: .utf8)

    let table = EndpointRouter.resolve(
        environment: [
            "GUJO_ENDPOINTS_FILE": ledgerURL.path,
            "GUJO_ENDPOINT_LEARN": "https://learn-env.invalid",
        ],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["learn"] == "https://learn-env.invalid")
    #expect(table["learn-prod"] == "https://learn.gujo.ai")
}

@Test("오버레이 키 — hyphen 과 underscore 를 서로 정규화하지 않는다")
func overlayDoesNotNormalizeHyphenAndUnderscore() {
    let table = EndpointRouter.resolve(
        environment: [
            "GUJO_ENDPOINT_CATALOG_PARQUET": "https://underscore-overlay.invalid",
        ],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["catalog_parquet"] == "https://underscore-overlay.invalid")
    #expect(table["catalog-parquet"] == "")
}

@Test("번들 폴백 — 공개·알려진 live 만 채우고 클러스터 키는 빈 문자열")
func bundledDefaultsKeepPublicHostsAndEmptyClusterKeys() {
    let table = EndpointRouter.resolve(environment: [:], homeDirectory: "/nonexistent-home")
    #expect(table["app"] == "https://gujo.ai")
    #expect(table["apps"] == "https://apps.gujo.ai")
    #expect(table["s3"] == "https://s3.ranode.net")
    #expect(table["infisical"] == "https://infisical.local.ranode.net")
    #expect(table["ranode-internal"] == "https://internal.ranode.net")
    let emptyClusterKeys = [
        "catalog-kr", "catalog-parquet", "emulator-control", "whisper", "mesh",
        "clipboard-sync", "prom", "otel", "grafana", "comfyui", "alertmanager",
        "llmwiki-archive", "gpu-panel",
    ]
    for key in emptyClusterKeys {
        #expect(table[key] == "", "cluster key \(key) must be empty in bundled defaults")
        #expect(URL(string: table[key] ?? "missing") == nil)
    }
}

@Test("원장 오버레이 — 빈 클러스터 키를 채운다")
func ledgerFillsEmptyClusterKey() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("endpoint-kit-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let ledgerURL = dir.appendingPathComponent("endpoints.json")
    try #"{"schema_version": 1, "endpoints": {"otel": "http://otel.example.invalid"}}"#
        .write(to: ledgerURL, atomically: true, encoding: .utf8)

    let table = EndpointRouter.resolve(
        environment: ["GUJO_ENDPOINTS_FILE": ledgerURL.path],
        homeDirectory: "/nonexistent-home"
    )
    #expect(table["otel"] == "http://otel.example.invalid")
    #expect(table["grafana"] == "")
}
