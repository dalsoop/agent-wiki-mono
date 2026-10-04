import KnowledgeBaseWikiCore
import SwiftUI

/// 모델 신빙성 — 모델 `model.law.credibility: LawCredibilityScreen?`, 기간 `model.setCredibilityPeriod(_:)`, 줄 펼침 `LawCredibilityScreen.items(for:)`.
/// 빈 화면(제목만) — 화면 본문은 다음 작업이 채운다. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
struct LawCredibilityView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawNavCredibility)).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-credibility")
    }
}
