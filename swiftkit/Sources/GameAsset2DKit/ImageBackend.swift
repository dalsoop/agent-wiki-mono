import Foundation
import InteropKit

/// 프롬프트(+캐논 참조) 1건을 실제 PNG 로 만들어 `outputPath` 에 남기는 생성 백엔드.
///
/// codex(`-i`)·god-tibo(`gti`)·(향후) 로컬 SD 등 서로 다른 생성 경로를 이 프로토콜 뒤로 격리한다.
/// SpriteForge 는 배치 큐·캐논 자동참조·프롬프트 템플릿·이력만 담당하고, "프롬프트→PNG" 의
/// 실제 호출 방식은 백엔드가 소유한다. 정본: docs/2d-game-assets-create/00-fleet-overview.md.
public protocol ImageBackend: Sendable {
    /// 안정적 식별자(레지스트리·이력 기록용). 예: `"codex-exec"`, `"god-tibo"`.
    var id: String { get }

    /// `request.basePrompt`(템플릿 본문, 백엔드별 지시 미포함)를 받아 `request.outputPath` 에
    /// PNG 파일을 만든다. 파일 생성 성공 여부는 호출자가 `outputPath` 존재로 최종 판정한다.
    func produce(_ request: ImageBackendRequest) async -> ProcessOutcome
}

/// 백엔드 1건 생성 요청. 백엔드 중립(codex/god-tibo 공통).
public struct ImageBackendRequest: Sendable {
    /// 템플릿 본문 프롬프트. "이 경로로 복사하라" 같은 **백엔드 고유 지시는 포함하지 않는다** —
    /// 그건 각 백엔드가 자기 방식대로(codex: stdin 지시 / god-tibo: `--output`) 붙인다.
    public let basePrompt: String
    /// 캐논 참조 이미지 경로. nil 이거나 파일이 없으면 참조 없이 생성.
    public let canonPath: String?
    /// 생성물이 최종적으로 있어야 할 경로.
    public let outputPath: String
    /// 작업 디렉터리(codex `--cd`).
    public let cwd: String
    /// 목표 픽셀 크기(선택). god-tibo `--size` 에 사용. nil 이면 백엔드 기본.
    public let width: Int?
    public let height: Int?
    /// 애니메이션 프레임 수(선택). 시트 전용 백엔드(Retro Diffusion `frames_duration`)가
    /// 프레임을 스스로 배치하는 데 쓴다. codex/god-tibo 는 프롬프트 텍스트로만 다루므로 무시.
    public let frames: Int?
    /// 생성 1건 타임아웃(초).
    public let timeout: TimeInterval

    public init(
        basePrompt: String,
        canonPath: String?,
        outputPath: String,
        cwd: String,
        width: Int? = nil,
        height: Int? = nil,
        frames: Int? = nil,
        timeout: TimeInterval
    ) {
        self.basePrompt = basePrompt
        self.canonPath = canonPath
        self.outputPath = outputPath
        self.cwd = cwd
        self.width = width
        self.height = height
        self.frames = frames
        self.timeout = timeout
    }
}

// MARK: - codex-exec 백엔드 (기본, 현행 동작 보존)

/// `codex exec --cd DIR --sandbox … -i canon -` 로 GPT image 를 호출하는 기본 백엔드.
///
/// codex 는 결과 PNG 를 `~/.codex/generated_images` 에 쓰고 지정 경로 복사를 보장하지 않으므로,
/// stdin 프롬프트에 "이 경로로 복사하라" 를 붙이고 + `CodexImageLocator` 로 회수해 그 틈을 메운다.
public struct CodexExecBackend: ImageBackend {
    public let id = "codex-exec"

    let codexPath: String
    let sandbox: String
    let runner: ProcessRunning
    let locator: CodexImageLocator

    public init(
        codexPath: String = "codex",
        sandbox: String = "workspace-write",
        runner: ProcessRunning = SystemProcessRunner(),
        locator: CodexImageLocator = CodexImageLocator()
    ) {
        self.codexPath = codexPath
        self.sandbox = sandbox
        self.runner = runner
        self.locator = locator
    }

    /// codex 는 결과를 파일로 저장할 때 stdin 프롬프트의 명시 경로 지시를 따른다.
    public static func copyInstruction(outputPath: String) -> String {
        """


        Generate this as an ACTUAL raster image using your image generation tool (do NOT write a script to draw it).
        After generating, copy the resulting PNG to this exact path: \(outputPath)
        """
    }

    public func produce(_ request: ImageBackendRequest) async -> ProcessOutcome {
        let fm = FileManager.default
        let prompt = request.basePrompt + Self.copyInstruction(outputPath: request.outputPath)

        var args = ["exec", "--cd", request.cwd, "--sandbox", sandbox]
        if let canon = request.canonPath, fm.fileExists(atPath: canon) {
            args += ["-i", canon]
        }
        args.append("-")   // 프롬프트는 stdin

        // 절대경로면 직접, 아니면 PATH 검색(env). codex 설치 위치(nvm/homebrew) 무관.
        let (launch, launchArgs) = codexPath.hasPrefix("/")
            ? (codexPath, args)
            : ("/usr/bin/env", [codexPath] + args)

        // codex 가 복사를 놓쳐도 되게, 실행 직전 시각을 기록해 두고 이후 최신 생성물을 회수한다.
        let started = Date().addingTimeInterval(-2)
        let outcome = await runner.run(launch, launchArgs, stdin: prompt, cwd: request.cwd, timeout: request.timeout)
        if !fm.fileExists(atPath: request.outputPath), outcome.ok {
            locator.ensureCopied(to: request.outputPath, since: started)
        }
        return outcome
    }
}

// MARK: - god-tibo 백엔드 (gti CLI)

/// `gti --prompt … --output PATH [--image canon] [--size WxH]` 로 GPT Image 2.0 를 호출하는 백엔드.
///
/// codex 의 비공개 ChatGPT 이미지 백엔드를 `~/.codex/auth.json` 재사용으로 부르는 얇은 CLI 래퍼다
/// (god-tibo-imagen). codex-exec 대비: 스킬/exec 왕복 없이 직접 호출, `--output` 직접 저장(회수 로직
/// 불필요), `--image` 로 캐논 참조를 1급으로 전달, `--size` 직접 지정.
///
/// ⚠️ 공식 API 가 아니라 예고 없이 깨질 수 있는 비공개 경로다. 반드시 이 어댑터 뒤에 격리하고
/// `health()`(호출자)로 감시하며 fallback 백엔드를 남겨둔다.
public struct GodTiboBackend: ImageBackend {
    public let id = "god-tibo"

    let gtiPath: String
    let runner: ProcessRunning

    public init(gtiPath: String = "gti", runner: ProcessRunning = SystemProcessRunner()) {
        self.gtiPath = gtiPath
        self.runner = runner
    }

    public func produce(_ request: ImageBackendRequest) async -> ProcessOutcome {
        let fm = FileManager.default
        // gti 는 --output 으로 직접 저장하므로 codex 식 "복사 지시" 는 붙이지 않는다.
        var args = ["--prompt", request.basePrompt, "--output", request.outputPath]
        if let canon = request.canonPath, fm.fileExists(atPath: canon) {
            args += ["--image", canon]
        }
        if let w = request.width, let h = request.height {
            args += ["--size", "\(w)x\(h)"]
        }

        // gti 의 shebang(`#!/usr/bin/env node`)이 node 를 찾아야 한다. GUI 앱은 최소 PATH 로
        // 실행돼 nvm/volta node 를 못 찾아 exit 127 이 난다 → `/usr/bin/env PATH=<보강> gti …`
        // 로 자식 PATH 에 node 위치를 주입한다. gtiPath 가 절대경로여도 shebang 은 PATH 를 탄다.
        let launchArgs = ["PATH=\(Self.augmentedPATH())", gtiPath] + args
        return await runner.run("/usr/bin/env", launchArgs, stdin: nil, cwd: request.cwd, timeout: request.timeout)
    }

    /// node 가 있을 법한 디렉터리(nvm 전 버전·homebrew·volta·표준)를 앞세우고 기존 PATH 를 뒤에 붙인다.
    static func augmentedPATH() -> String {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var dirs: [String] = []
        // nvm: 설치된 node 버전 bin 을 최신 우선으로.
        let nvm = home + "/.nvm/versions/node"
        do {
            let versions = try fm.contentsOfDirectory(atPath: nvm)
            for v in versions.sorted().reversed() { dirs.append("\(nvm)/\(v)/bin") }
        } catch {}
        dirs += [HostPlatform.homebrewBin, "/usr/local/bin", home + "/.volta/bin",
                 home + "/.asdf/shims", "/usr/bin", "/bin"]
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        if !existing.isEmpty { dirs.append(existing) }
        return dirs.joined(separator: ":")
    }
}
