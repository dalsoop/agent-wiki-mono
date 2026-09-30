import KnowledgeBaseWikiCore
import SwiftUI

/// 근거 추가 — 발행 확인 문구가 명시된 폼. 유사 근거가 있으면 재현으로 연결 제안.
struct AddEvidenceSheet: View {
    @Bindable var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var origin = ""
    @State private var aliases = ""
    @State private var domain = ""
    @State private var kind = ""
    @State private var knowledge = ""
    @State private var classificationReason = ""
    @State private var supportsID: String?

    private var classification: LedgerClassificationInput? {
        LedgerClassificationInput(
            domain: domain,
            kind: kind,
            knowledge: knowledge,
            reason: classificationReason)
    }

    private var aliasValues: [String] {
        aliases.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var similar: [LedgerDocument] {
        let words = Set(title.lowercased().split(separator: " ").map(String.init))
        guard !words.isEmpty else { return [] }
        return model.evidenceDocuments.map(\.document).filter { candidate in
            let candidateWords = Set(candidate.title.lowercased().split(separator: " ").map(String.init))
            return !words.intersection(candidateWords).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("근거 추가").font(.headline)
            TextField("제목", text: $title).textFieldStyle(.roundedBorder)
            TextField("출처 URL·경로 (스크랩·수집 근거라면 필수에 가깝게)", text: $origin)
                .textFieldStyle(.roundedBorder)
            TextField("검색 별칭 (쉼표 구분 · 예: agent-request, 자동승인)", text: $aliases)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $bodyText)
                .font(.body)
                .frame(width: 460, height: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            AddEvidenceClassificationBox(
                domain: $domain, kind: $kind, knowledge: $knowledge,
                reason: $classificationReason)
            AddEvidenceSimilarPicks(similar: similar, supportsID: $supportsID)
            AddEvidencePublishBar(
                supportsID: supportsID,
                canPublish: classification != nil
                    && !title.trimmingCharacters(in: .whitespaces).isEmpty
                    && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                dismiss()
            } publish: {
                guard let classification else { return }
                model.publishEvidence(
                    title: title, body: bodyText,
                    origin: origin.isEmpty ? nil : origin,
                    supports: supportsID,
                    classification: classification,
                    aliases: aliasValues)
                dismiss()
            }
        }
        .padding(20)
    }
}

private struct AddEvidenceClassificationBox: View {
    @Binding var domain: String
    @Binding var kind: String
    @Binding var knowledge: String
    @Binding var reason: String

    var body: some View {
        GroupBox("분류 — 발행과 동시에 선별 객체로 남습니다") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("도메인", selection: $domain) {
                        Text("도메인 선택").tag("")
                        ForEach(LedgerClassificationInput.domains, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("종류", selection: $kind) {
                        Text("종류 선택").tag("")
                        ForEach(LedgerClassificationInput.kinds, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("지식", selection: $knowledge) {
                        Text("지식층 선택").tag("")
                        ForEach(LedgerClassificationInput.knowledgeKinds, id: \.self) { Text($0).tag($0) }
                    }
                }
                TextField("왜 이 분류인가 (필수 — 원장에 남습니다)", text: $reason)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 2)
        }
    }
}

private struct AddEvidenceSimilarPicks: View {
    let similar: [LedgerDocument]
    @Binding var supportsID: String?

    var body: some View {
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("비슷한 근거가 이미 있습니다 — 같은 취지면 재현으로 연결하세요:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(similar.prefix(3)) { candidate in
                    Toggle(
                        candidate.title.replacingOccurrences(of: "근거: ", with: ""),
                        isOn: Binding(
                            get: { supportsID == candidate.id },
                            set: { supportsID = $0 ? candidate.id : nil }))
                    .toggleStyle(.checkbox).font(.callout)
                }
            }
        }
    }
}

private struct AddEvidencePublishBar: View {
    let supportsID: String?
    let canPublish: Bool
    let cancel: () -> Void
    let publish: () -> Void

    var body: some View {
        HStack {
            Text("발행 후에는 수정·삭제할 수 없습니다.")
                .font(.caption).foregroundStyle(.orange)
            Spacer()
            Button("취소", action: cancel)
            Button(supportsID == nil ? "발행" : "재현으로 발행", action: publish)
                .keyboardShortcut(.defaultAction)
                .disabled(!canPublish)
        }
    }
}

/// 재현/반박 스탬프 — 한 줄 메모와 함께 발행.
struct ReinforceSheet: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    let contradicts: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(contradicts ? "반박 발행" : "재현 확인 발행").font(.headline)
            Text(contradicts
                 ? "이 근거와 상충하는 사실을 확인했다면 반박을 발행합니다 — 근거는 지워지지 않고 나란히 남습니다."
                 : "이 근거가 여전히 사실임을 다시 확인했다면 재현을 발행합니다 — 지지도가 오르고 신선도가 리셋됩니다.")
                .font(.caption).foregroundStyle(.secondary).frame(width: 380)
            TextField(contradicts ? "무엇이 상충하나" : "무엇으로 재확인했나 (필수 — 판단 기록)", text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("발행") {
                    model.reinforce(document, contradicts: contradicts, note: note)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}

/// 파이프라인 단계 배지 — 전 화면 공통 어휘(수집=주황, 발행=파랑, 검증=초록, 작성=보라).
struct StageBadge: View {
    let stage: LedgerModel.PipelineStage

    private var color: Color {
        switch stage {
        case .collected: return .orange
        case .bridged: return .blue
        case .verified: return .green
        case .revised: return .gray
        case .authored: return .purple
        }
    }

    var body: some View {
        Text(stage.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 저작 provenance 패널 — **이 판단이 어떤 조건에서 나왔나.**
///
/// author 문자열만으로는 같은 `agent:claude@macbook` 이 어떤 모델로 무엇을 읽고
/// 얼마를 써서 이 결론에 왔는지 알 수 없다. 원장의 절반이 자동 배치 산출물이라
/// (import-classifier 222 · taxonomy-drafter 202 · wiki-maintainer 418), 나중에
/// "이 판단을 믿어도 되나"를 재려면 이 조건이 남아 있어야 한다.
///
/// 없는 값을 0 으로 채우지 않는다 — "0 토큰으로 썼다"는 거짓이 되기 때문이다.
/// 기록이 없으면 없다고 그대로 말한다.
struct AuthoringPanel: View {
    let authoring: Authoring?

    var body: some View {
        if let authoring, !authoring.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("저작 기록", systemImage: "cpu")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    field("모델", authoring.model ?? authoring.runtime)
                    field("토큰", tokenText)
                    field("컨텍스트", authoring.contextObjects.map { "\($0)객체" })
                    field("기기", authoring.host)
                }
                if let session = authoring.session {
                    Text("세션 \(session)").font(.caption2).foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        } else {
            Label("저작 기록 없음 — 이 객체는 모델·비용·컨텍스트를 남기지 않았다",
                  systemImage: "cpu")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var tokenText: String? {
        guard let authoring else { return nil }
        if let i = authoring.tokensIn, let o = authoring.tokensOut { return "\(i)→\(o)" }
        if let o = authoring.tokensOut { return "출력 \(o)" }
        return nil
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.tertiary)
                Text(value).font(.caption.monospacedDigit())
            }
        }
    }
}
