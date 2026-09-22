import Foundation
import OnboardingKit

/// photo-origin-ledger CLI 소비자 앱의 첫 실행 조건. 원장 자체·뷰어·VPN 은 항목이 달라 앱에 둔다.
public enum OnboardingJudge {
    public static let contract = 1
    public typealias Snapshot = OnboardingSnapshot

    public enum ItemID: String, Sendable, Equatable, CaseIterable {
        case ledgerCLI
        case ledgerReady
    }

    public static func evaluate(ledgerInstalled: Bool, ledgerReady: Bool, dismissed: Bool) -> Snapshot {
        OnboardingSnapshot(
            items: [
                OnboardingItem(id: ItemID.ledgerCLI.rawValue, done: ledgerInstalled),
                OnboardingItem(id: ItemID.ledgerReady.rawValue, done: ledgerReady),
            ],
            dismissed: dismissed
        )
    }
}
