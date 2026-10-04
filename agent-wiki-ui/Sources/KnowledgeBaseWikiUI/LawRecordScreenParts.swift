import KnowledgeBaseWikiCore
import SwiftUI

// 목차·기록 목록·기록 상세가 같이 쓰는 작은 표시 조각 — 열거값의 화면 이름, 짧은 id, 칸 한 줄, 기록으로 가는 줄.
// 화면은 모델 값만 읽는다(원장 폴더를 훑지 않는다).

enum LawRecordText {
    /// 목차와 같은 id 앞 8자리.
    static func shortID(_ id: String) -> String { String(id.prefix(8)) }

    @MainActor static func memoryKind(_ kind: LawMemoryKind) -> String {
        switch kind {
        case .person: L(.lawRecordKindPerson)
        case .feedback: L(.lawRecordKindFeedback)
        case .project: L(.lawRecordKindProject)
        case .reference: L(.lawRecordKindReference)
        case .unclassified: L(.lawRecordKindUnclassified)
        }
    }

    @MainActor static func caseKind(_ kind: LawCourtCaseKind) -> String {
        switch kind {
        case .appeal: L(.lawRecordDisputeAppeal)
        case .proposal: L(.lawRecordDisputeProposal)
        }
    }

    /// 심급(`LawRulingLevel` 원시값). 모르는 값은 그대로.
    @MainActor static func level(_ raw: String) -> String {
        switch raw {
        case "appellate": L(.lawRecordLevelAppellate)
        case "supreme": L(.lawRecordLevelSupreme)
        default: raw
        }
    }

    /// 결정 결과(`LawRulingOutcome` 원시값). 모르는 값은 그대로.
    @MainActor static func outcome(_ raw: String) -> String {
        switch raw {
        case "uphold": L(.lawRecordOutcomeUphold)
        case "overturn": L(.lawRecordOutcomeOverturn)
        case "refer": L(.lawRecordOutcomeRefer)
        case "approve": L(.lawRecordOutcomeApprove)
        case "reject": L(.lawRecordOutcomeReject)
        default: raw
        }
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// 남은 시간(이의 기간) — 시스템 지역 형식, 큰 단위 둘까지.
    static func remaining(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? ""
    }
}

/// 출처 패널의 칸 한 줄 — 값이 없으면 그리지 않는다.
struct LawRecordField: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 상세의 한 절 — 제목과 내용, 내용이 없으면 "없음".
struct LawRecordSection<Content: View>: View {
    let title: String
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if isEmpty {
                Text(L(.lawRecordNone)).font(.callout).foregroundStyle(.secondary)
            } else {
                content()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 기록으로 가는 줄 — 누르면 `model.showLawRecord(id:)`.
struct LawRecordLink: View {
    @Bindable var model: LedgerModel
    let id: String
    let text: String
    var detail: String?

    var body: some View {
        Button {
            model.showLawRecord(id: id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LawRecordText.shortID(id))
                    .font(.callout.monospaced())
                    .foregroundStyle(NamuTheme.internalLink)
                Text(text).font(.callout).lineLimit(2)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
