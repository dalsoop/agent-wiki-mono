import Foundation

/// 바 아이템의 아이콘 출처
public enum BarItemIcon: Sendable, Equatable {
    case appBundle(String)
    case symbol(String)
    case customPath(String)
}

/// 에이전트 및 방의 생체 신호 도트
public enum BarStatusDot: String, Sendable, Equatable {
    case none
    case running
    case waiting
    case error
    case idle
}

/// 타일 우상단 상태 뱃지
public struct BarBadge: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case attention  // ❓ 질문 대기, 입력 대기
        case hold       // ⏸ 게이트 홀드, 차단
        case count      // 숫자 알림
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind = .count) {
        self.text = text
        self.kind = kind
    }
}

/// 독 바에 렌더링되는 모든 타일의 단일 정본 계약
public struct UnifiedBarItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: BarItemIcon
    public let statusDot: BarStatusDot
    public let badge: BarBadge?
    public let subjobCount: Int
    public let runningSubjobCount: Int
    public let workdir: String?
    public let children: [UnifiedBarItem]
    public let model: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: BarItemIcon,
        statusDot: BarStatusDot = .none,
        badge: BarBadge? = nil,
        subjobCount: Int = 0,
        runningSubjobCount: Int = 0,
        workdir: String? = nil,
        children: [UnifiedBarItem] = [],
        model: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.statusDot = statusDot
        self.badge = badge
        self.subjobCount = subjobCount
        self.runningSubjobCount = runningSubjobCount
        self.workdir = workdir
        self.children = children
        self.model = model
    }

    public var hasSubjobs: Bool {
        subjobCount > 0
    }

    public var hasChildren: Bool {
        !children.isEmpty
    }

    public var totalSubagentCount: Int {
        children.count + children.reduce(0) { $0 + $1.totalSubagentCount }
    }

    public var subjobString: String? {
        guard hasSubjobs else { return nil }
        if runningSubjobCount > 0 {
            return "↳ \(subjobCount) (\(runningSubjobCount) run)"
        }
        return "↳ \(subjobCount)"
    }
}
