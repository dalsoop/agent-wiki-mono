import Foundation

/// 첫 실행 설정 한 항목. `id` 는 앱이 정한다(원장 CLI, 공유 마운트 등).
public struct OnboardingItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var done: Bool
    public var required: Bool
    public var title: String?
    public var detail: String?
    public var symbol: String?
    public var actionTitle: String?
    public var action: (@MainActor @Sendable () -> Void)?

    public init(
        id: String,
        done: Bool,
        required: Bool = true,
        title: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        actionTitle: String? = nil,
        action: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.done = done
        self.required = required
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
    }

    public static func == (lhs: OnboardingItem, rhs: OnboardingItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.done == rhs.done &&
        lhs.required == rhs.required &&
        lhs.title == rhs.title &&
        lhs.detail == rhs.detail &&
        lhs.symbol == rhs.symbol &&
        lhs.actionTitle == rhs.actionTitle
    }
}

/// 필수 항목이 모두 참일 때만 온보딩을 끝낸다. 건너뛰기는 `dismissed`.
public struct OnboardingSnapshot: Sendable, Equatable {
    public var items: [OnboardingItem]
    public var dismissed: Bool

    public init(items: [OnboardingItem], dismissed: Bool) {
        self.items = items
        self.dismissed = dismissed
    }

    /// 아직 안 끝난 필수 항목 id.
    public var missing: [String] {
        items.filter { $0.required && !$0.done }.map(\.id)
    }

    public var satisfied: Bool { missing.isEmpty }

    /// `satisfied` 별칭. 기존 앱 Judge 가 `complete` 를 썼다.
    public var complete: Bool { satisfied }

    public var shouldPresent: Bool { !satisfied && !dismissed }
}
