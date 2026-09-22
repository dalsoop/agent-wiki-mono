import XCTest
@testable import GameAsset2DKit

final class GameAsset2DKitTests: XCTestCase {
    func testTemplateRenderAndUnresolved() {
        let t = PromptTemplate("Hello {{name}}, {{missing}}")
        XCTAssertEqual(t.render(["name": "Gaya"]), "Hello Gaya, {{missing}}")
        XCTAssertEqual(PromptTemplate("Hello {{name}}").render(["name": "X"]).unresolvedCount, 0)
        XCTAssertEqual(t.unresolvedTokens.sorted(), ["missing", "name"])
    }

    func testBuildPromptContainsRulesAndOutputPath() {
        let forge = SpriteForge()
        let m = GenManifest(character: "a heroine", canon: "canon.png", outputDir: "out",
                            sprites: [SpriteSpec(name: "heroine_idle", motion: "idle", frames: 8)])
        let prompt = forge.buildPrompt(m, m.sprites[0], outputPath: "/tmp/heroine_idle.png")
        XCTAssertTrue(prompt.contains("8 frames"))
        XCTAssertTrue(prompt.contains("Do NOT mirror"))
        XCTAssertTrue(prompt.contains("/tmp/heroine_idle.png"))
    }

    func testManifestRoundTrip() throws {
        let m = GenManifest(character: "c", canon: "canon.png", outputDir: "raw",
                            sprites: [SpriteSpec(name: "run", motion: "run cycle", frames: 8, palette: "16")])
        let tmp = NSTemporaryDirectory() + "gen_\(UUID().uuidString).json"
        try m.save(tmp)
        XCTAssertEqual(try GenManifest.load(tmp), m)
    }

    func testLocatorRecoversNewestImage() throws {
        let root = NSTemporaryDirectory() + "genimg_\(UUID().uuidString)"
        let sub = root + "/019abc"
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        let since = Date()
        let img = sub + "/exec-1.png"
        FileManager.default.createFile(atPath: img, contents: Data([0x89, 0x50]))

        let loc = CodexImageLocator(root: root)
        let found = loc.newestImage(since: since.addingTimeInterval(-5))
        XCTAssertEqual(found.map { ($0 as NSString).lastPathComponent }, "exec-1.png")
        XCTAssertNotNil(found)

        let target = NSTemporaryDirectory() + "out_\(UUID().uuidString)/heroine.png"
        XCTAssertTrue(loc.ensureCopied(to: target, since: since.addingTimeInterval(-5)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))
        // 이미 있으면 그대로 true
        XCTAssertTrue(loc.ensureCopied(to: target, since: since))
    }

    func testGenerateUsesMockRunnerAndRecordsHistory() async throws {
        let dir = NSTemporaryDirectory() + "forge_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // 캐논 파일 존재하게
        FileManager.default.createFile(atPath: dir + "/canon.png", contents: Data([1, 2, 3]))

        let mock = MockRunner(dir: dir)
        let forge = SpriteForge(runner: mock)
        let m = GenManifest(character: "c", canon: "canon.png", outputDir: "raw",
                            sprites: [SpriteSpec(name: "idle", motion: "idle", frames: 4)])
        let histPath = dir + "/history.jsonl"
        let results = await forge.generate(manifest: m, manifestDir: dir, history: GenHistory(path: histPath))

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].ok)
        XCTAssertTrue(mock.lastArgs.contains("-i"))           // 캐논 참조 첨부됨
        XCTAssertTrue(mock.lastArgs.contains("-"))            // stdin 프롬프트
        XCTAssertTrue(mock.lastStdin?.contains("idle") ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: histPath))
    }

    func testRegistryRoundTripAndBackendFactory() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "reg_\(UUID().uuidString)/image-backend.json")
        let reg = ImageBackendRegistry(url: url)
        // 파일 없으면 기본(codex-exec).
        XCTAssertEqual(reg.load().selection, .codexExec)
        // 저장 → 재로드.
        try reg.save(ImageBackendSettings(selection: .godTibo, codexPath: "codex", gtiPath: "/opt/homebrew/bin/gti"))
        let loaded = reg.load()
        XCTAssertEqual(loaded.selection, .godTibo)
        XCTAssertEqual(loaded.gtiPath, "/opt/homebrew/bin/gti")
        // 팩토리가 선택에 맞는 백엔드를 만든다.
        XCTAssertEqual(makeImageBackend(loaded).id, "god-tibo")
        XCTAssertEqual(makeImageBackend(ImageBackendSettings(selection: .codexExec)).id, "codex-exec")
    }

    func testRegistryToleratesCorruptFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "reg_\(UUID().uuidString)/image-backend.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json ".utf8).write(to: url)
        // 깨진 파일이 fleet 전체를 막지 않고 기본으로 복구.
        XCTAssertEqual(ImageBackendRegistry(url: url).load().selection, .codexExec)
    }

    func testRetroDiffusionRequestBodyAndWrite() async throws {
        let dir = NSTemporaryDirectory() + "rd_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/canon.png", contents: Data([1, 2, 3, 4]))
        let out = dir + "/idle.png"

        // 1x1 PNG 최소 바이트를 base64 로 돌려주는 목.
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let http = MockHTTP(status: 200,
                            responseJSON: ["base64_images": [pngBytes.base64EncodedString()]])
        let backend = RetroDiffusionBackend(apiKey: "test-key", promptStyle: "rd_pro__default", http: http)
        let req = ImageBackendRequest(basePrompt: "hero idle", canonPath: dir + "/canon.png",
                                      outputPath: out, cwd: dir, width: 128, height: 128, frames: 7, timeout: 60)

        // 요청 본문 검증(별도 계산).
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: backend.requestBody(for: req)) as? [String: Any])
        XCTAssertEqual(body["prompt"] as? String, "hero idle")
        XCTAssertEqual(body["prompt_style"] as? String, "rd_pro__default")
        XCTAssertEqual(body["frames_duration"] as? Int, 6)              // 7 → 가장 가까운 허용값 6
        XCTAssertNotNil(body["reference_images"])                        // 캐논 첨부됨

        let outcome = await backend.produce(req)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(http.lastHeaders["X-RD-Token"], "test-key")
        XCTAssertTrue(http.lastURL?.absoluteString.hasSuffix("/inferences") ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out))       // base64 → PNG 저장
    }

    func testRetroDiffusionSnapFrames() {
        XCTAssertEqual(RetroDiffusionBackend.snappedFrames(4), 4)
        XCTAssertEqual(RetroDiffusionBackend.snappedFrames(7), 6)
        XCTAssertEqual(RetroDiffusionBackend.snappedFrames(9), 8)
        XCTAssertEqual(RetroDiffusionBackend.snappedFrames(100), 16)
        XCTAssertNil(RetroDiffusionBackend.snappedFrames(1))
        XCTAssertNil(RetroDiffusionBackend.snappedFrames(nil))
    }

    func testRetroDiffusionHTTPErrorSurfacesExitCode() async throws {
        let http = MockHTTP(status: 401, responseJSON: ["error": "unauthorized"])
        let backend = RetroDiffusionBackend(apiKey: "", http: http)
        let outcome = await backend.produce(ImageBackendRequest(
            basePrompt: "x", canonPath: nil, outputPath: NSTemporaryDirectory() + "no.png", cwd: NSTemporaryDirectory(), timeout: 10))
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.exitCode, 401)
    }

    func testGodTiboBackendPassesOutputAndImageFlags() async throws {
        let dir = NSTemporaryDirectory() + "gti_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/canon.png", contents: Data([1, 2, 3]))
        let out = dir + "/hero_idle.png"

        // gti 흉내: --output 경로에 직접 파일을 쓴다(codex 식 stdin 지시 없음).
        let mock = GtiMockRunner(shouldWriteOutput: true)
        let backend = GodTiboBackend(runner: mock)
        let outcome = await backend.produce(ImageBackendRequest(
            basePrompt: "a heroine idle sheet, 8 frames",
            canonPath: dir + "/canon.png", outputPath: out, cwd: dir, width: 1024, height: 1024, timeout: 60))

        XCTAssertTrue(outcome.ok)
        XCTAssertTrue(mock.lastArgs.contains("--prompt"))
        XCTAssertTrue(mock.lastArgs.contains("--output"))
        XCTAssertTrue(mock.lastArgs.contains(out))                 // 직접 저장 경로
        XCTAssertTrue(mock.lastArgs.contains("--image"))           // 캐논 참조
        XCTAssertTrue(mock.lastArgs.contains("1024x1024"))         // --size
        XCTAssertNil(mock.lastStdin)                                // stdin 프롬프트 없음
        XCTAssertTrue(FileManager.default.fileExists(atPath: out))
        // node PATH 보강: /usr/bin/env 로 PATH= 를 주입한다.
        XCTAssertTrue(mock.lastArgs.first?.hasPrefix("PATH=") ?? false)
        XCTAssertTrue(mock.lastArgs.first?.contains("/opt/homebrew/bin") ?? false)
    }

    func testGodTiboAugmentedPathIncludesNodeDirs() {
        let path = GodTiboBackend.augmentedPATH()
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
    }

    func testForgeUsesInjectedGodTiboBackendAndRecordsHistory() async throws {
        let dir = NSTemporaryDirectory() + "forge_gti_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/canon.png", contents: Data([1, 2, 3]))

        let mock = GtiMockRunner(shouldWriteOutput: true)
        let forge = SpriteForge(backend: GodTiboBackend(runner: mock))
        let m = GenManifest(character: "c", canon: "canon.png", outputDir: "raw",
                            sprites: [SpriteSpec(name: "idle", motion: "idle", frames: 4)])
        let histPath = dir + "/history.jsonl"
        let results = await forge.generate(manifest: m, manifestDir: dir, history: GenHistory(path: histPath))

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].ok)
        XCTAssertTrue(mock.lastArgs.contains("--output"))          // god-tibo 경로로 갔다
        XCTAssertTrue(mock.lastArgs.contains("--image"))           // 캐논 참조 자동 첨부
        XCTAssertTrue(FileManager.default.fileExists(atPath: histPath))
    }
}

private extension String {
    var unresolvedCount: Int { PromptTemplate(self).unresolvedTokens.count }
}

/// codex 대신 출력 파일을 만들어주는 목 러너.
final class MockRunner: ProcessRunning, @unchecked Sendable {
    let dir: String
    var lastArgs: [String] = []
    var lastStdin: String?
    init(dir: String) { self.dir = dir }

    func run(_ launchPath: String, _ arguments: [String], stdin: String?, cwd: String?, timeout: TimeInterval?) async -> ProcessOutcome {
        lastArgs = arguments
        lastStdin = stdin
        // 프롬프트에서 저장 경로를 파싱해 파일 생성(실제 codex 흉내).
        if let stdin, let range = stdin.range(of: "exact path: ") {
            let path = String(stdin[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            FileManager.default.createFile(atPath: path, contents: Data([0]))
        }
        return ProcessOutcome(stdout: "ok", stderr: "", exitCode: 0)
    }
}

/// HTTP 목: 지정 상태코드 + JSON 을 돌려주고 마지막 요청을 기록한다.
final class MockHTTP: HTTPPosting, @unchecked Sendable {
    let status: Int
    let responseJSON: [String: Any]
    var lastURL: URL?
    var lastHeaders: [String: String] = [:]
    var lastBody: Data?
    init(status: Int, responseJSON: [String: Any]) {
        self.status = status
        self.responseJSON = responseJSON
    }
    func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> (Data, Int) {
        lastURL = url; lastHeaders = headers; lastBody = body
        let data = (try? JSONSerialization.data(withJSONObject: responseJSON)) ?? Data()
        return (data, status)
    }
}

/// gti 흉내: `--output PATH` 인자를 파싱해 그 경로에 직접 파일을 쓴다.
final class GtiMockRunner: ProcessRunning, @unchecked Sendable {
    let shouldWriteOutput: Bool
    var lastArgs: [String] = []
    var lastStdin: String?
    init(shouldWriteOutput: Bool) { self.shouldWriteOutput = shouldWriteOutput }

    func run(_ launchPath: String, _ arguments: [String], stdin: String?, cwd: String?, timeout: TimeInterval?) async -> ProcessOutcome {
        lastArgs = arguments
        lastStdin = stdin
        if shouldWriteOutput, let i = arguments.firstIndex(of: "--output"), i + 1 < arguments.count {
            FileManager.default.createFile(atPath: arguments[i + 1], contents: Data([0]))
        }
        return ProcessOutcome(stdout: "ok", stderr: "", exitCode: 0)
    }
}
