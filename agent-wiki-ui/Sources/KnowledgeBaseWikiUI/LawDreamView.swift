import KnowledgeBaseWikiCore
import SwiftUI

/// 드리밍 — 모델 `model.law.dream: LawDreamScreen?`, 묶음 고르기 `model.selectDreamBatch(_:)` → `model.law.batchChanges`, 되돌리기 `model.revertDreamBatch(_:)`, 재개 `model.resumeDreaming()`, 결과 `model.law.actionMessage`.
/// 빈 화면(제목만) — 화면 본문은 다음 작업이 채운다. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
struct LawDreamView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawNavDream)).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-dream")
    }
}
