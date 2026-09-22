import Foundation

/// 어떤 생성 백엔드를 쓸지의 선택지. 레지스트리·설정 UI·이력이 공유하는 안정 식별자.
public enum ImageBackendSelection: String, Codable, CaseIterable, Sendable {
    /// codex exec 경유 GPT image(현행 기본, 항상 사용 가능한 fallback).
    case codexExec = "codex-exec"
    /// god-tibo-imagen(`gti`) 경유 GPT Image 2.0 — `~/.codex/auth.json` 재사용, `--image` 참조 1급.
    case godTibo = "god-tibo"
    /// Retro Diffusion HTTP API — 스프라이트 시트 학습 모델(프레임 일관성 강). 유료·env 키 필요.
    case retroDiffusion = "retro-diffusion"

    public var displayName: String {
        switch self {
        case .codexExec: return "codex exec (기본)"
        case .godTibo: return "god-tibo (gti)"
        case .retroDiffusion: return "Retro Diffusion (시트 전용·유료)"
        }
    }
}

/// fleet 공유 백엔드 선택 SSOT — `~/.agent-apps/image-backend.json`.
///
/// 관리 앱(GameAssetsStudio 설정)이 여기 쓰고, 모든 이미지 생성 앱(독립 스테이지 앱 포함)이
/// 여기서 읽어 **한 곳에서 고르면 전부 같은 백엔드**를 쓴다. secret 은 담지 않는다 —
/// god-tibo 는 `~/.codex/auth.json` 을 재사용하고, 경로/식별자만 기록한다.
public struct ImageBackendSettings: Codable, Equatable, Sendable {
    public var selection: ImageBackendSelection
    public var codexPath: String
    public var gtiPath: String
    /// Retro Diffusion 스타일 모델 id. 키는 여기 저장 안 함(env `RETRODIFFUSION_API_KEY`).
    public var retroStyle: String

    public init(selection: ImageBackendSelection = .codexExec,
                codexPath: String = "codex",
                gtiPath: String = "gti",
                retroStyle: String = "rd_plus__default") {
        self.selection = selection
        self.codexPath = codexPath
        self.gtiPath = gtiPath
        self.retroStyle = retroStyle
    }

    private enum CodingKeys: String, CodingKey { case selection, codexPath, gtiPath, retroStyle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 미지 값·누락에 관대: 깨진 파일이 fleet 전체를 막지 않게 기본으로 복구.
        self.selection = (try? c.decode(ImageBackendSelection.self, forKey: .selection)) ?? .codexExec
        self.codexPath = (try? c.decode(String.self, forKey: .codexPath)) ?? "codex"
        self.gtiPath = (try? c.decode(String.self, forKey: .gtiPath)) ?? "gti"
        self.retroStyle = (try? c.decode(String.self, forKey: .retroStyle)) ?? "rd_plus__default"
    }
}

/// `~/.agent-apps/image-backend.json` 읽기/쓰기(원자적). 테스트는 임시 경로를 주입한다.
public struct ImageBackendRegistry: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".agent-apps/image-backend.json")
    }

    /// 현재 선택. 파일이 없거나 깨졌으면 기본값(codex-exec).
    public func load() -> ImageBackendSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(ImageBackendSettings.self, from: data)
        else { return ImageBackendSettings() }
        return settings
    }

    /// 원자적 저장(temp + rename). 디렉터리는 자동 생성.
    public func save(_ settings: ImageBackendSettings) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        let tmp = dir.appendingPathComponent(".image-backend.json.tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: [.atomic])
        do {
            try FileManager.default.removeItem(at: url)
        } catch {}
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}

/// 선택 + 경로로 실제 `ImageBackend` 를 만든다. fleet 앱이 SpriteForge 에 주입할 backend 를 이걸로 얻는다.
public func makeImageBackend(
    _ settings: ImageBackendSettings,
    runner: ProcessRunning = SystemProcessRunner(),
    locator: CodexImageLocator = CodexImageLocator()
) -> ImageBackend {
    switch settings.selection {
    case .codexExec:
        return CodexExecBackend(codexPath: settings.codexPath, runner: runner, locator: locator)
    case .godTibo:
        return GodTiboBackend(gtiPath: settings.gtiPath, runner: runner)
    case .retroDiffusion:
        // 키는 env 에서 주입(레지스트리에 원문 저장 안 함). 없으면 빈 키 → produce 가 HTTP 401 로 실패.
        let key = ProcessInfo.processInfo.environment["RETRODIFFUSION_API_KEY"] ?? ""
        return RetroDiffusionBackend(apiKey: key, promptStyle: settings.retroStyle)
    }
}

/// 백엔드 준비 상태 점검(설정 UI 표시용). 비공개 경로인 god-tibo 의 함정을 미리 잡는다.
public struct ImageBackendHealth: Sendable, Equatable {
    public enum State: String, Sendable { case ready, actionRequired }
    public let state: State
    public let summary: String

    /// 선택된 백엔드가 실행 가능한 상태인지 확인.
    /// - god-tibo: `gti` 실행파일 확인 + `~/.codex/auth.json` 존재(로그인 재사용 전제).
    /// - codex-exec: `codex` 실행파일 확인.
    public static func check(_ settings: ImageBackendSettings) -> ImageBackendHealth {
        switch settings.selection {
        case .codexExec:
            return resolvable(settings.codexPath)
                ? .init(state: .ready, summary: "codex 실행 가능.")
                : .init(state: .actionRequired, summary: "codex 를 PATH 에서 찾지 못했습니다: \(settings.codexPath)")
        case .godTibo:
            guard resolvable(settings.gtiPath) else {
                return .init(state: .actionRequired,
                             summary: "gti 를 찾지 못했습니다 — `npm i -g god-tibo-imagen` 후 경로 확인.")
            }
            let auth = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
            guard FileManager.default.fileExists(atPath: auth.path) else {
                return .init(state: .actionRequired,
                             summary: "~/.codex/auth.json 없음 — Codex/ChatGPT 로그인 후 재시도.")
            }
            return .init(state: .ready, summary: "gti 실행 가능 · Codex 로그인 확인됨.")
        case .retroDiffusion:
            let hasKey = !(ProcessInfo.processInfo.environment["RETRODIFFUSION_API_KEY"] ?? "").isEmpty
            return hasKey
                ? .init(state: .ready, summary: "Retro Diffusion API 키(env) 확인됨.")
                : .init(state: .actionRequired,
                        summary: "환경변수 RETRODIFFUSION_API_KEY 미설정 — 유료 API 키를 export 하세요.")
        }
    }

    /// 절대경로면 실행권한 확인, 아니면 PATH 검색.
    private static func resolvable(_ path: String) -> Bool {
        let fm = FileManager.default
        if path.hasPrefix("/") { return fm.isExecutableFile(atPath: path) }
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
            .split(separator: ":").map(String.init)
        return dirs.contains { fm.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent(path)) }
    }
}
