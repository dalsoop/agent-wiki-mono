import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

struct PromotionQueueView: View {
    @Bindable var model: LedgerModel
    @State private var selectedID: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("승격 후보").font(.headline)
                        Text("재사용할 지식만 gujo wiki로").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.promotionCandidates.count)").font(.caption.monospacedDigit())
                }.padding(14)
                Divider()
                List(model.promotionCandidates, selection: $selectedID) { object in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(object.title ?? "제목 없음").fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
                        Text("\(object.effectiveType ?? "knowledge") · \(String(object.id.prefix(10)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.tag(object.id)
                }
                .overlay {
                    if model.promotionCandidates.isEmpty {
                        ContentUnavailableView(L(.PromotionQueueViewEmptyTitle), systemImage: "arrow.up.forward.square",
                            description: Text(L(.PromotionQueueViewEmptyDescription)))
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 320)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("\(model.currentWorldName ?? "이 world") → 공유 gujo wiki").font(.title2.bold())
                    Text("복사하지 않습니다. 출처(repo commit 또는 world)를 고정한 미리보기와 양방향 영수증을 발행합니다.")
                        .foregroundStyle(.secondary)
                    if let selectedID,
                       let source = model.objects.first(where: { $0.id == selectedID }) {
                        sourceCard(source)
                        Button {
                            model.previewPromotion(objectID: selectedID)
                        } label: { Label("승격 미리보기", systemImage: "doc.text.magnifyingglass") }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isReadOnlyWorld)
                    } else {
                        Label("왼쪽에서 후보를 선택하세요", systemImage: "cursorarrow.click")
                            .foregroundStyle(.secondary)
                    }
                    if let preview = model.promotionPreview,
                       preview.sourceObjectId == selectedID {
                        previewCard(preview)
                    }
                    if let result = model.promotionResult { receiptCard(result.receipt) }
                    if let message = model.promotionMessage {
                        Label(
                            message,
                            systemImage: model.promotionMessageIsError
                                ? "exclamationmark.triangle.fill"
                                : (model.promotionResult == nil ? "info.circle" : "checkmark.seal.fill"))
                            .font(.callout)
                            .foregroundStyle(
                                model.promotionMessageIsError
                                    ? Color.red
                                    : (model.promotionResult == nil ? Color.secondary : Color.green))
                    }
                    if !model.promotionReceipts.isEmpty {
                        receiptsSection
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        // HSplitView 는 스스로 안 늘어난다
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("repository-promotion")
        .onChange(of: selectedID) {
            model.promotionPreview = nil
            model.promotionResult = nil
            model.promotionMessage = nil
            model.promotionMessageIsError = false
        }
    }

    private func sourceCard(_ source: LedgerObject) -> some View {
        GroupBox("선택한 저장소 객체") {
            VStack(alignment: .leading, spacing: 5) {
                Text(source.title ?? "제목 없음").font(.headline)
                Text(source.body).lineLimit(5).frame(minWidth: 0).foregroundStyle(.secondary)
                Text(source.id).font(.caption.monospaced()).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
    }

    private func previewCard(_ preview: PromotionPreview) -> some View {
        GroupBox("발행 전 provenance 미리보기") {
            VStack(alignment: .leading, spacing: 7) {
                if preview.sourceKind == "repository" {
                    receiptRow("sourceRepoId", preview.sourceRepoId ?? "-")
                    receiptRow("sourceCommit", preview.sourceCommit ?? "-")
                } else {
                    receiptRow("sourceWorld", preview.sourceWorldName ?? "-")
                }
                receiptRow("sourceObjectId", preview.sourceObjectId)
                receiptRow("targetWorld", preview.targetWorld)
                receiptRow("citation", "promotes → \(preview.promotesCitation.id)")
                Divider()
                Button {
                    model.publishPromotion()
                } label: { Label("확인하고 gujo wiki에 승격", systemImage: "arrow.up.forward.app.fill") }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(model.isReadOnlyWorld)
            }.padding(.top, 5)
        }
    }

    private func receiptCard(_ receipt: PromotionReceipt) -> some View {
        GroupBox("발행 영수증") {
            VStack(alignment: .leading, spacing: 7) {
                Label("양방향 영수증 검증 가능", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                receiptRow("source object", receipt.sourceObjectId)
                receiptRow("gujo object", receipt.targetObjectId)
                if receipt.sourceKind == "repository" {
                    receiptRow("commit", receipt.sourceCommit ?? "-")
                } else {
                    receiptRow("world", receipt.sourceWorldName ?? "-")
                }
                receiptRow("promoted by", receipt.promotedBy)
            }.padding(.top, 5)
        }
    }

    private var receiptsSection: some View {
        GroupBox("최근 승격 영수증") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(model.promotionReceipts.prefix(8).enumerated()), id: \.offset) { _, receipt in
                    HStack {
                        Image(systemName: "link.badge.plus").foregroundStyle(.purple)
                        Text(String(receipt.sourceObjectId.prefix(10))).font(.caption.monospaced())
                        Image(systemName: "arrow.right").font(.caption)
                        Text(String(receipt.targetObjectId.prefix(10))).font(.caption.monospaced())
                        Spacer()
                        Text(receipt.promotedAt, format: .dateTime.month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 5)
        }
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).frame(width: 110, alignment: .trailing).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
