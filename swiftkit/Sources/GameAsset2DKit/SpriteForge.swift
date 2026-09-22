import Foundation

/// codex(GPT image)로 스프라이트 시트를 배치 생성하는 오케스트레이터.
///
/// 즉흥 CLI 호출(`cat prompt | codex exec ... -i canon -`)을 **캐논 자동참조 + 프롬프트 템플릿 +
/// 이력 기록** 이 붙은 재현 가능한 흐름으로 대체한다. 정본: docs/GAMEMAKER-SWIFT-APP-FLEET.md.
public struct SpriteForge: Sendable {
    public struct Config: Sendable {
        /// codex 실행 파일 경로.
        public var codexPath: String
        /// 샌드박스 모드(기본 workspace-write).
        public var sandbox: String
        /// 생성 1건 타임아웃(초).
        public var timeout: TimeInterval
        public init(codexPath: String = "codex",
                    sandbox: String = "workspace-write",
                    timeout: TimeInterval = 600) {
            self.codexPath = codexPath
            self.sandbox = sandbox
            self.timeout = timeout
        }
    }

    /// 생성 1건 결과.
    public struct Result: Sendable {
        public let spec: SpriteSpec
        public let outputPath: String
        public let ok: Bool
        public let stderr: String
    }

    let runner: ProcessRunning
    let config: Config
    let locator: CodexImageLocator
    let backend: ImageBackend

    /// 기본 백엔드는 codex-exec(현행 동작). `backend` 를 명시하면 god-tibo 등으로 교체된다.
    /// `runner`/`config`/`locator` 는 기본 백엔드 구성과 하위호환 시그니처를 위해 유지한다.
    public init(runner: ProcessRunning = SystemProcessRunner(),
                config: Config = .init(),
                locator: CodexImageLocator = CodexImageLocator(),
                backend: ImageBackend? = nil) {
        self.runner = runner
        self.config = config
        self.locator = locator
        self.backend = backend ?? CodexExecBackend(
            codexPath: config.codexPath, sandbox: config.sandbox, runner: runner, locator: locator)
    }

    /// 매니페스트 한 모션의 템플릿 본문 프롬프트(백엔드 중립, 저장 지시 미포함).
    public func buildBasePrompt(_ manifest: GenManifest, _ spec: SpriteSpec) -> String {
        SpritePromptRules.sheetTemplate.render([
            "character": manifest.character,
            "motion": spec.motion,
            "frames": String(spec.frames),
            "palette": spec.palette,
            "extra": spec.extra,
        ])
    }

    /// 매니페스트 한 모션의 완성 프롬프트를 만든다(codex 식 출력 경로 저장 지시 포함).
    /// 하위호환용 — 배치 생성 경로는 `buildBasePrompt` + 백엔드가 각자 지시를 붙인다.
    public func buildPrompt(_ manifest: GenManifest, _ spec: SpriteSpec, outputPath: String) -> String {
        buildBasePrompt(manifest, spec) + CodexExecBackend.copyInstruction(outputPath: outputPath)
    }

    /// 매니페스트를 배치 생성한다. `only` 지정 시 해당 sprite 이름만.
    /// 진행 로그는 `onProgress` 로 스트림(CLI/GUI 공용).
    public func generate(
        manifest: GenManifest,
        manifestDir: String,
        history: GenHistory?,
        only: Set<String>? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> [Result] {
        let fm = FileManager.default
        let outDir = resolve(manifest.outputDir, base: manifestDir)
        do { try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true) } catch { _ = error }
        let canonPath = resolve(manifest.canon, base: manifestDir)

        var results: [Result] = []
        for spec in manifest.sprites {
            if let only, !only.contains(spec.name) { continue }
            let outPath = (outDir as NSString).appendingPathComponent("\(spec.name).png")
            let basePrompt = buildBasePrompt(manifest, spec)
            onProgress?("▶ \(spec.name) (\(spec.frames)f) [\(backend.id)] …")

            let request = ImageBackendRequest(
                basePrompt: basePrompt,
                canonPath: fm.fileExists(atPath: canonPath) ? canonPath : nil,
                outputPath: outPath,
                cwd: manifestDir,
                frames: spec.frames,
                timeout: config.timeout)
            let outcome = await backend.produce(request)
            let produced = fm.fileExists(atPath: outPath)
            let ok = outcome.ok && produced

            try? history?.append(GenRecord(
                identity: .init(
                    timestamp: Self.now(),
                    spriteName: spec.name,
                    motion: spec.motion,
                    frames: spec.frames
                ),
                paths: .init(canon: canonPath, prompt: basePrompt, outputPath: outPath),
                ok: ok,
                exitCode: outcome.exitCode
            ))

            onProgress?(ok ? "  ✓ \(outPath)" : "  ✗ \(spec.name) (exit \(outcome.exitCode), produced=\(produced))")
            results.append(Result(spec: spec, outputPath: outPath, ok: ok, stderr: outcome.stderr))
        }
        return results
    }

    /// 상대경로면 매니페스트 디렉터리 기준으로 해석.
    func resolve(_ path: String, base: String) -> String {
        if path.hasPrefix("/") { return path }
        return (base as NSString).appendingPathComponent(path)
    }

    static func now() -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: Date())
    }
}
