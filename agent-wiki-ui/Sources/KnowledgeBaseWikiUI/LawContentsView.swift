import KnowledgeBaseWikiCore
import SwiftUI

/// 목차(ledger 3 원장의 첫 화면) — 모델 `model.law.contents: LawContentsScreen?`, 목차 줄의 기록으로 `model.showLawRecord(id:)`.
/// 빈 화면(제목만) — 화면 본문은 다음 작업이 채운다. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
struct LawContentsView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawNavContents)).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-contents")
    }
}
