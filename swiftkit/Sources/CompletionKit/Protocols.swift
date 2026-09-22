import CoreGraphics
import Foundation

// CompletionKit — 로컬 LLM 인라인 완성 앱들(keyboard-typer 산문 / code-ghost 코드)이 공유하는
// 입력·삽입·오버레이 계층. 이 파일은 앱 비종속 공유 타입(문맥·프로토콜·삽입 결과)을 정의한다.
// LLM 엔진·프롬프트·조정자는 각 앱이 소유한다(산문/코드로 다르므로).

/// 캐럿 주변 텍스트 문맥. prefix(앞)+suffix(뒤) 를 둘 다 담아 FIM(code-ghost)도 지원한다.
public struct TextContext: Sendable, Equatable {
    public var bundleID: String?
    public var appName: String?
    /// 캐럿 앞 텍스트.
    public var prefix: String
    /// 캐럿 뒤 텍스트(FIM 용 — 산문 앱은 빈 문자열).
    public var suffix: String
    /// 캐럿 화면 좌표 — Cocoa bottom-left 원점(오버레이 배치용).
    public var caretScreenRect: CGRect?
    /// 포커스 요소 전체 화면 rect — Cocoa bottom-left(캐럿 rect 미지원 앱의 오버레이 폴백).
    /// Electron(VSCode/Cursor 등)은 캐럿 픽셀 bounds 를 AX 로 노출하지 않으므로,
    /// 마우스 위치 대신 편집 영역 안에 오버레이를 앵커하기 위해 쓴다.
    public var elementScreenRect: CGRect?
    /// 대상 필드 폰트 크기 추정(모르면 nil).
    public var fontPointSize: CGFloat?
    /// 포커스 요소 식별자(요소 바뀌면 값 바뀜 — CFHash 기반).
    public var elementID: UInt
    /// 편집 중 문서 파일명(예: `Main.swift`) — FIM 언어 힌트용. 모르면 nil.
    public var fileName: String?
    /// 편집 중 문서 전체 경로(document 기반 앱만) — 교차 파일 문맥 수집용. 모르면 nil.
    public var filePath: String?
    public var capturedAt: Date

    public struct App: Sendable, Equatable {
        public var bundleID: String?
        public var appName: String?
        public init(bundleID: String?, appName: String?) {
            self.bundleID = bundleID
            self.appName = appName
        }
    }

    public struct Geometry: Sendable, Equatable {
        public var caretScreenRect: CGRect?
        public var elementScreenRect: CGRect?
        public var fontPointSize: CGFloat?
        public init(
            caretScreenRect: CGRect?,
            fontPointSize: CGFloat?,
            elementScreenRect: CGRect? = nil
        ) {
            self.caretScreenRect = caretScreenRect
            self.elementScreenRect = elementScreenRect
            self.fontPointSize = fontPointSize
        }
    }

    public struct Document: Sendable, Equatable {
        public var elementID: UInt
        public var fileName: String?
        public var filePath: String?
        public var capturedAt: Date
        public init(
            elementID: UInt,
            fileName: String? = nil,
            filePath: String? = nil,
            capturedAt: Date = Date()
        ) {
            self.elementID = elementID
            self.fileName = fileName
            self.filePath = filePath
            self.capturedAt = capturedAt
        }
    }

    public init(
        app: App,
        prefix: String,
        suffix: String,
        geometry: Geometry,
        document: Document
    ) {
        self.bundleID = app.bundleID
        self.appName = app.appName
        self.prefix = prefix
        self.suffix = suffix
        self.caretScreenRect = geometry.caretScreenRect
        self.fontPointSize = geometry.fontPointSize
        self.elementID = document.elementID
        self.elementScreenRect = geometry.elementScreenRect
        self.fileName = document.fileName
        self.filePath = document.filePath
        self.capturedAt = document.capturedAt
    }
}

/// 포커스 감시 이벤트.
public enum FocusEvent: Sendable {
    case contextChanged(TextContext)
    case focusLost
}

/// 오버레이 표시자(구현: 각 앱의 GhostOverlayController, @MainActor).
@MainActor
public protocol SuggestionPresenting: AnyObject {
    func show(suggestion: String, context: TextContext)
    func hide()
    var isSuggestionVisible: Bool { get }
    var currentSuggestion: String? { get }
    func updateAlternatives(_ alternatives: [String])
}

/// 수락 키 이벤트 수신자. KeyEventTap 은 아래가 true 를 반환하면 그 키를 소비(삼킴)한다.
@MainActor
public protocol AcceptKeyHandling: AnyObject {
    var wantsAcceptKeys: Bool { get }
    func handleAcceptFull() -> Bool
    func handleAcceptWord() -> Bool
    /// 첫 줄만 수락. 기본 구현은 handleAcceptWord 로 폴백(줄 액션 미사용 앱 호환).
    func handleAcceptLine() -> Bool
    func handleDismiss() -> Bool
    func handleGlobalToggle() -> Bool
    func handleForceActivate()
    /// 수정 모드 발동(선택 코드 재작성). true 반환 시에만 키 소비 — 미사용 앱(기본 false)은
    /// 키를 안 삼켜 ⌥⌘K 가 다른 앱 단축키로 통과한다.
    func handleEditActivate() -> Bool
    func handleAlternative(_ index: Int) -> Bool
    var wantsDigitKeys: Bool { get }
    /// 콘텐츠 키 입력이 통과할 때(소비 안 함) 호출 — 자동 트리거(디바운스 완성)용.
    /// 기본 구현은 아무것도 안 함(수동 트리거만 쓰는 앱은 무시).
    func handleTypingActivity()
}

public extension AcceptKeyHandling {
    func handleTypingActivity() {}
    func handleAcceptLine() -> Bool { handleAcceptWord() }
    func handleEditActivate() -> Bool { false }
}

/// 삽입 결과.
public enum InsertResult: Sendable, Equatable {
    case success
    case appIgnored
    case failed
}

/// 삽입 실패 종류.
public enum InsertIssue: String, Sendable, Equatable, CaseIterable {
    case failed        // E03 — 삽입 자체 실패
    case appIgnored    // E05 — 앱이 삽입을 무시
    public var code: String {
        switch self { case .failed: "E03"; case .appIgnored: "E05" }
    }
    public var isPermissionRelated: Bool { self == .failed }
}

/// 텍스트 삽입기 프로토콜(구현: TextInserter, @MainActor).
@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String) -> InsertResult
    func replaceBackward(utf16Count: Int, with text: String) -> InsertResult
}
