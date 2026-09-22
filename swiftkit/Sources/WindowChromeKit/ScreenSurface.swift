import Foundation

/// 화면 한 칸 = 코드 한 좌표. 칸 id 가 원장 키이고, source 가 파일이다.
public struct ScreenSurface: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// `Module/File.swift:symbol` 형태. 줄 번호는 뷰가 바뀌면 흔들리니 심지 않는다.
    public var source: String
    /// 이 칸을 채우는 소유 CLI 명령.
    public var readCommand: String

    public init(id: String, title: String, source: String, readCommand: String) {
        self.id = id
        self.title = title
        self.source = source
        self.readCommand = readCommand
    }
}

/// 세 칸 카탈로그가 기본으로 찍는 표면.
public struct ThreeColumnSurfaces: Sendable, Equatable {
    public var sidebar: ScreenSurface
    public var content: ScreenSurface
    public var inspector: ScreenSurface

    public init(sidebar: ScreenSurface, content: ScreenSurface, inspector: ScreenSurface) {
        self.sidebar = sidebar
        self.content = content
        self.inspector = inspector
    }

    public var all: [ScreenSurface] { [sidebar, content, inspector] }

    /// `#fileID`("Module/File.swift") 에서 앱 이름을 뽑아 칸 id 를 찍는다.
    /// 셸 3종이 같은 파생을 각자 복붙하고 있었다 — 여기가 정본이다.
    public static func derived(file: String, readCommand: String = "status --json") -> ThreeColumnSurfaces {
        let module = file.split(separator: "/").first.map(String.init) ?? ""
        return ThreeColumnSurfaces(
            app: module.isEmpty ? "app" : module,
            readCommand: readCommand,
            sidebarSource: file,
            contentSource: file,
            inspectorSource: file
        )
    }

    /// `app.sidebar` / `app.content` / `app.inspector` 칸 id 를 한 번에 찍는다.
    public init(
        app: String,
        readCommand: String,
        sidebarSource: String,
        contentSource: String,
        inspectorSource: String,
        /// 원장·기계 id. 화면 표시는 `WindowChromeStrings` 가 KR/EN 로 붙인다.
        sidebarTitle: String = "sidebar",
        contentTitle: String = "content",
        inspectorTitle: String = "inspector"
    ) {
        self.sidebar = ScreenSurface(
            id: "\(app).sidebar", title: sidebarTitle,
            source: sidebarSource, readCommand: readCommand
        )
        self.content = ScreenSurface(
            id: "\(app).content", title: contentTitle,
            source: contentSource, readCommand: readCommand
        )
        self.inspector = ScreenSurface(
            id: "\(app).inspector", title: inspectorTitle,
            source: inspectorSource, readCommand: readCommand
        )
    }
}
