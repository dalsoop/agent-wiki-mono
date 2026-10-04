import KnowledgeBaseWikiCore
import SwiftUI

/// 드리밍 묶음 상세 — 그 묶음이 바꾼 기록(원장별, 신규·개정·폐지)과 각 기록으로 이동, 묶음 되돌리기 버튼.
/// 기록 목록은 `model.selectDreamBatch(_:)` 가 배경에서 읽은 `model.law.batchChanges` 다.
struct LawDreamBatchSection: View {
    @Bindable var model: LedgerModel
    let batch: String
    let dream: LawDreamScreen
    let onRevert: () -> Void

    var body: some View {
        let changes = model.law.batchChanges
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if changes.isEmpty {
                    Text(L(.LawDreamBatchEmpty)).font(.callout).foregroundStyle(.secondary)
                } else {
                    LawDreamChangeList(changes: changes, onOpen: { model.showLawRecord(id: $0) })
                }
                if !model.isReadOnlyWorld {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button(role: .destructive, action: onRevert) {
                            Label(L(.LawDreamRevert), systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!dream.canWrite || changes.isEmpty)
                        .accessibilityIdentifier("law-dream-revert")
                        LawDreamWriteDenials(denials: dream.writeDenials)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(L(.LawDreamBatchSection, batch)).font(.headline)
                Spacer()
                Button(L(.LawDreamCloseBatch)) { model.selectDreamBatch(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("law-dream-batch-detail")
    }
}

/// 묶음이 바꾼 기록 — 원장별 묶음, 한 줄에 종류(신규·개정·폐지)·제목·id.
struct LawDreamChangeList: View {
    let changes: [LawBatchChange]
    /// 기록 id 를 눌렀을 때 기록 상세로 간다. nil 이면 이동 없음(확인 창).
    var onOpen: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.grouped(changes), id: \.world) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.world) (\(group.changes.count))").font(.callout.weight(.semibold))
                    ForEach(group.changes) { change in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(kindText(change.kind))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                            Text(change.record.record.title ?? String(change.id.prefix(8)))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            if let onOpen {
                                Button(String(change.id.prefix(8))) { onOpen(change.id) }
                                    .buttonStyle(.link)
                                    .font(.caption.monospaced())
                            } else {
                                Text(String(change.id.prefix(8))).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func kindText(_ kind: LawBatchChange.Kind) -> String {
        switch kind {
        case .enacted: return L(.LawDreamChangeEnacted)
        case .amended(let target): return "\(L(.LawDreamChangeAmended)) \(target.prefix(8))"
        case .repealed(let target): return "\(L(.LawDreamChangeRepealed)) \(target.prefix(8))"
        }
    }

    /// 원장 순서를 지키며 원장별로 묶는다.
    static func grouped(_ changes: [LawBatchChange]) -> [(world: String, changes: [LawBatchChange])] {
        var order: [String] = []
        var byWorld: [String: [LawBatchChange]] = [:]
        for change in changes {
            if byWorld[change.world] == nil { order.append(change.world) }
            byWorld[change.world, default: []].append(change)
        }
        return order.map { ($0, byWorld[$0] ?? []) }
    }
}

/// 되돌리기 확인 창을 띄우는 요청(묶음 id).
struct LawDreamRevertRequest: Identifiable {
    let batch: String
    var id: String { batch }
}

/// 되돌리기 확인 창 — 원장별로 되돌릴 기록 목록을 보여 준 뒤에만 실행한다.
struct LawDreamRevertConfirmSheet: View {
    let batch: String
    let changes: [LawBatchChange]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.LawDreamRevertTitle, batch)).font(.title3.weight(.semibold))
            Text(L(.LawDreamRevertDesc)).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LawDreamChangeList(changes: changes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack {
                Spacer()
                Button(L(.LawDreamCancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive, action: onConfirm) {
                    Text(L(.LawDreamRevertConfirm))
                }
                .disabled(changes.isEmpty)
                .accessibilityIdentifier("law-dream-revert-confirm")
            }
        }
        .padding(20)
        .frame(minWidth: 480)
        .accessibilityIdentifier("law-dream-revert-sheet")
    }
}

