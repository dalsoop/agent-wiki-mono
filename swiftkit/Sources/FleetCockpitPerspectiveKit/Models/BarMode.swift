import Foundation

/// 단일 독 바의 3대 표시 모드
public enum BarMode: String, CaseIterable, Sendable, Codable {
    /// 1. 앱바: macOS 실행 중인 일반 앱 및 즐겨찾기(Pinned) 타일
    case appBar
    /// 2. 에이전트바: 활성 대화형 AI 세션 (agy, claude, codex) 타일
    case agentBar
    /// 3. 룸바: agent-work-todo 활성 Room(방) 타일 및 하위 AWO 파이프라인 잡
    case roomBar

    public var title: String {
        switch self {
        case .appBar: return "Apps"
        case .agentBar: return "Agents"
        case .roomBar: return "Rooms"
        }
    }

    public var systemImage: String {
        switch self {
        case .appBar: return "macwindow.on.rectangle"
        case .agentBar: return "sparkles"
        case .roomBar: return "person.2.badge.gearshape"
        }
    }

    public var shortcutIndex: Int {
        switch self {
        case .appBar: return 1
        case .agentBar: return 2
        case .roomBar: return 3
        }
    }

    public func next() -> BarMode {
        switch self {
        case .appBar: return .agentBar
        case .agentBar: return .roomBar
        case .roomBar: return .appBar
        }
    }

    public func previous() -> BarMode {
        switch self {
        case .appBar: return .roomBar
        case .agentBar: return .appBar
        case .roomBar: return .agentBar
        }
    }
}
