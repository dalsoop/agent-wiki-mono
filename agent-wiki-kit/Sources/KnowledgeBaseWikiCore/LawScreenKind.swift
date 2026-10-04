import Foundation

// 화면이 원장 형식을 판정하는 한 자리 — 설정(`WorldBindingCatalog`)으로만 판정한다.
// ledger 3 원장(`isLedgerThree`)이면 새 원장 화면(목차·기록·심급·드리밍·모델 신빙성), 아니면 지금 화면.
// 원장 폴더가 git 저장소인지로 "저장소 위키"를 판정하지 않는다 — ledger 3 원장 세 폴더는 git 저장소 하나를 이루지만
// 저장소 위키가 아니다(2026-10-04 화면 확인: Studio 가 agent-law 를 저장소 위키로 읽고 repoId·브랜치·커밋을 보였다).
// 층은 설정에 기록된 값만 쓴다(이름·경로로 추정하지 않는다).
// 근거: docs/business-rules.md "# agent-law(ledger 3)" 원장 구성(층은 설정에 기록), 결정 0007·0008.

/// ledger 3 원장 화면의 메뉴(옆 메뉴 순서). 목차가 첫 화면이다.
public enum LawScreenMenu: String, CaseIterable, Sendable, Equatable {
    case contents
    case records
    case court
    case dream
    case credibility
}

/// 열린 원장 하나의 화면 판정.
public struct LawLedgerScreenKind: Sendable, Equatable {
    public let worldName: String
    /// 설정상 ledger 3 원장(원장 키나 전신을 가짐).
    public let isLedgerThree: Bool
    /// 다른 원장의 전신으로 지정된(보관된) 원장 — 읽기 전용.
    public let isArchived: Bool
    /// 설정에 기록된 층. 기록되지 않았으면 nil(이름·경로로 추정하지 않는다).
    public let recordedLayer: WikiWorldLayer?

    public init(worldName: String, catalog: WorldBindingCatalog) {
        self.worldName = worldName
        isLedgerThree = catalog.isLedgerThree(worldName)
        isArchived = catalog.isArchived(worldName)
        recordedLayer = catalog.world(named: worldName)?.layer.flatMap(WikiWorldLayer.init(rawValue:))
    }

    /// 새 원장 화면을 쓰는가.
    public var usesLawScreens: Bool { isLedgerThree }

    /// 옆 메뉴 — ledger 3 원장이면 다섯 개, 아니면 비어 있다(지금 화면의 메뉴를 쓴다).
    public var menus: [LawScreenMenu] { isLedgerThree ? LawScreenMenu.allCases : [] }

    /// 원장 폴더를 저장소(git)로 살펴 저장소 위키 표시(repoId·브랜치·커밋·저장소 무결성)를 해도 되는가.
    /// ledger 3 원장은 저장소 위키가 아니므로 살피지 않는다.
    public var mayInspectRepository: Bool { !isLedgerThree }

    /// "보관된 원장(전신) — 읽기 전용" 표시를 하고 편집 버튼을 숨긴다.
    public var isReadOnly: Bool { isArchived }
}
