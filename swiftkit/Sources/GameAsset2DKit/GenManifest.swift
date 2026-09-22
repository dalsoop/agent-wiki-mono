import Foundation

/// 한 모션 시트의 생성 명세.
public struct SpriteSpec: Codable, Sendable, Equatable {
    /// 출력 파일 base 이름(확장자 제외). 예: "heroine_idle".
    public var name: String
    /// 모션 서술. 예: "idle breathing loop".
    public var motion: String
    /// 프레임 수.
    public var frames: Int
    /// 팔레트 힌트. 예: "cool teal armor, warm skin, 16 colors".
    public var palette: String
    /// 추가 프롬프트(모션별 디테일). 선택.
    public var extra: String

    public init(name: String, motion: String, frames: Int, palette: String = "16-color game palette", extra: String = "") {
        self.name = name
        self.motion = motion
        self.frames = frames
        self.palette = palette
        self.extra = extra
    }
}

/// 캐릭터 한 명의 배치 생성 매니페스트(재현 단위).
///
/// JSON 파일로 저장·버전관리한다. `spriteforge gen <manifest.json>` 이 이걸 소비한다.
public struct GenManifest: Codable, Sendable, Equatable {
    /// 캐릭터 서술(프롬프트의 {{character}}).
    public var character: String
    /// 캐논 참조 이미지 경로(codex `-i`). 매니페스트 파일 기준 상대경로 허용.
    public var canon: String
    /// 원본 png 출력 디렉터리.
    public var outputDir: String
    /// 생성할 모션 목록.
    public var sprites: [SpriteSpec]

    public init(character: String, canon: String, outputDir: String, sprites: [SpriteSpec]) {
        self.character = character
        self.canon = canon
        self.outputDir = outputDir
        self.sprites = sprites
    }

    public static func load(_ path: String) throws -> GenManifest {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(GenManifest.self, from: data)
    }

    public func save(_ path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: path))
    }
}
