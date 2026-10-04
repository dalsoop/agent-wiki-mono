import KnowledgeBaseWikiCore
import SwiftUI

/// 기록 목록 — 모델 `model.law.records: [LawRecordListRow]`, 거르기 `model.law.recordFilter` / `model.setLawRecordFilter(_:)`, 줄을 누르면 `model.showLawRecord(id:)`.
/// 빈 화면(제목만) — 화면 본문은 다음 작업이 채운다. 표시 모델은 엔진이 배경에서 만들어 `model.law` 에 둔다.
struct LawRecordsView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawNavRecords)).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("law-screen-records")
    }
}
