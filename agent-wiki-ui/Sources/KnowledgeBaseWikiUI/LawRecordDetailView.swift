import KnowledgeBaseWikiCore
import SwiftUI

/// 기록 상세(출처 패널) — 모델 `model.law.recordDetail: LawRecordDetail?`(선택 id `model.law.selectedRecordID`), 닫기 `model.closeLawRecord()`.
/// 빈 화면(제목만) — 화면 본문은 다음 작업이 채운다. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
struct LawRecordDetailView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawNavRecordDetail)).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-record-detail")
    }
}
