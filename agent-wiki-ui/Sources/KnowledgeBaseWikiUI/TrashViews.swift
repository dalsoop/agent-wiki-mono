import KnowledgeBaseWikiCore
import SwiftUI

/// 휴지통 상세 — 철회 사유 + 원문 + 복원 발행.
struct TrashDetailView: View {
    @Bindable var model: LedgerModel
    let row: (document: LedgerDocument, retraction: LedgerObject)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(row.document.title).font(.title2.weight(.semibold)).strikethrough()
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("폐기 사유 — \(row.retraction.author) · \(row.retraction.published, format: .dateTime.month().day().hour().minute())",
                              systemImage: "trash")
                            .font(.callout.weight(.medium)).foregroundStyle(.red)
                        Text(row.retraction.body).font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !model.isReadOnlyWorld {  // 보관된 원장(전신)은 복원 발행하지 않는다
                    Button {
                        model.restore(document: row.document)
                    } label: {
                        Label("복원 발행 (restores)", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider()
                Text("원문").font(.headline)
                MarkdownBody(text: row.document.head.body)
            }
            .padding(16)
        }
    }
}
