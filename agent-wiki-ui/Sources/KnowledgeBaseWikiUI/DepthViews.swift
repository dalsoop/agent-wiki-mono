import KnowledgeBaseWikiCore
import SwiftUI
import UniformTypeIdentifiers

/// 수집함 — 유입 원자료를 한 장씩 크게 놓고 킵/버림/나중에. 이메일 트리아지 감각.
struct TriageView: View {
    @Bindable var model: LedgerModel
    @State private var index = 0
    @State private var discardReason = ""
    @State private var showDiscard = false
    @State private var keepRationale = ""
    @State private var showKeep = false
    @State private var showIngest = false
    @State private var pasteText = ""
    @State private var pasteTitle = ""
    @State private var pasteProject = ""
    @State private var dropTargeted = false

    private var queue: [(document: LedgerDocument, strength: EvidenceStrength)] {
        model.triageQueue
    }

    /// 원문 추가 박스 — 붙여넣기(텍스트) + 파일 드롭(PDF/오디오는 CLI 추출). 위키 직접 X, 수집함으로.
    private var ingestBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { showIngest.toggle() } } label: {
                Label(showIngest ? "원문 추가 닫기" : "원문 추가 (붙여넣기·파일)",
                      systemImage: showIngest ? "chevron.down" : "plus.circle")
                    .font(.callout.weight(.medium))
            }.buttonStyle(.plain)
            if showIngest {
                TextField("제목(선택)", text: $pasteTitle).textFieldStyle(.roundedBorder)
                TextField("프로젝트(선택)", text: $pasteProject).textFieldStyle(.roundedBorder)
                TextField("여기에 유튜브 스크립트 등 원문을 붙여넣기…", text: $pasteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(4...12).frame(minWidth: 0)
                HStack {
                    Button {
                        model.captureText(title: pasteTitle, project: pasteProject, body: pasteText)
                        pasteText = ""; pasteTitle = ""
                    } label: { Label("붙여넣기 수집", systemImage: "doc.on.clipboard") }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                // 파일 드롭 존
                RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(dropTargeted ? NamuTheme.brand : .secondary)
                    .frame(height: 56)
                    .overlay {
                        Label("PDF·오디오·텍스트 파일을 여기로 끌어놓기", systemImage: "tray.and.arrow.down")
                            .font(.caption).foregroundStyle(dropTargeted ? NamuTheme.brand : .secondary)
                    }
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                        ingestDroppedFiles(providers)
                        return true
                    }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private func ingestDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    model.captureFile(path: url.path, project: pasteProject)
                }
            }
        }
    }

    private func keepIfValid(_ document: LedgerDocument) {
        model.screenIn(document, rationale: keepRationale)
        keepRationale = ""
        showKeep = false
    }

    var body: some View {
        let queue = queue
        if queue.isEmpty {
            VStack(spacing: 0) {
                ingestBox
                ContentUnavailableView(L(.DepthViewsEmptyInboxTitle), systemImage: "tray",
                    description: Text(L(.DepthViewsEmptyInboxDesc)))
            }
        } else {
            let safeIndex = min(index, queue.count - 1)
            let row = queue[safeIndex]
            VStack(spacing: 0) {
                ingestBox
                HStack {
                    Text("수집함 \(safeIndex + 1) / \(queue.count)")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Text(row.document.title.replacingOccurrences(of: "근거: ", with: ""))
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 6) {
                            Text(row.document.head.author == "human" ? "내가 수집" : row.document.head.author)
                            Text(row.document.head.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        originLink(row.document.head.origin)
                        Divider()
                        Text(row.document.head.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(20)
                }
                Divider()
                HStack(spacing: 12) {
                    Button {
                        showDiscard = true
                    } label: {
                        Label("버림", systemImage: "trash")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("나중에") { index = (safeIndex + 1) % max(queue.count, 1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                    Spacer()
                    Button {
                        showKeep = true
                    } label: {
                        Label("킵 — 선별", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(14)
            }
            .sheet(isPresented: $showKeep) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("선별 사유 (판단 기록으로 남습니다)").font(.headline)
                    TextField("왜 볼 가치가 있나 — 예: 공식 문서, 재현 절차 포함", text: $keepRationale)
                        .textFieldStyle(.roundedBorder).frame(width: 360)
                        .onSubmit { keepIfValid(row.document) }
                    HStack {
                        Spacer()
                        Button("취소") { showKeep = false }
                        Button("선별") { keepIfValid(row.document) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(keepRationale.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(20)
            }
            .sheet(isPresented: $showDiscard) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("버림 사유 (역사에 남습니다)").font(.headline)
                    TextField("예: 광고성, 중복, 관련 없음", text: $discardReason)
                        .textFieldStyle(.roundedBorder).frame(width: 320)
                    HStack {
                        Spacer()
                        Button("취소") { showDiscard = false }
                        Button("버림") {
                            model.discard(row.document, reason: discardReason)
                            discardReason = ""
                            showDiscard = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func originLink(_ origin: String?) -> some View {
        if let origin, let url = URL(string: origin) {
            Link(origin, destination: url).font(.caption)
        }
    }
}

/// 심사대 — 정제본별 인용 근거의 검증 상태 + 확립 게이트 진행.
struct ReviewBoardView: View {
    @Bindable var model: LedgerModel

    var body: some View {
        let pending = model.pendingReviewDigests
        if model.digestDocuments.isEmpty {
            ContentUnavailableView(L(.DepthViewsEmptyReviewTitle), systemImage: "checklist",
                description: Text(L(.DepthViewsEmptyReviewDesc)))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !pending.isEmpty {
                        Text("판정 대기 \(pending.count)").font(.headline).padding(.horizontal, 12).padding(.top, 8)
                        ForEach(pending) { digest in
                            DigestReviewRow(model: model, digest: digest).padding(.horizontal, 12)
                        }
                        Divider().padding(.vertical, 4)
                    }
                    Text("근거 검증 게이트").font(.headline).padding(.horizontal, 12)
                    gateList
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var gateList: some View {
        VStack(spacing: 6) {
            ForEach(model.digestDocuments) { digest in
                let rows = model.reviewRows(of: digest)
                let gate = model.gate(of: digest)
                TapDisclosure {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Image(systemName: row.contradicts > 0 ? "bolt.fill"
                                  : row.supports > 0 ? "checkmark.seal.fill" : "questionmark.circle")
                                .foregroundStyle(row.contradicts > 0 ? .red
                                                 : row.supports > 0 ? .green : .secondary)
                            Text((row.evidence.title ?? "(무제)").replacingOccurrences(of: "근거: ", with: ""))
                                .lineLimit(1).frame(minWidth: 0)
                            Text(row.status).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            verificationButton(row)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(digest.title).fontWeight(.medium)
                            establishedBadge(gate.passed)
                        }
                        HStack(spacing: 10) {
                            gateItem("재현 \(gate.supports)/2", done: gate.supports >= 2)
                            gateItem("반박 \(gate.contradicts)", done: gate.contradicts == 0)
                            gateItem(String(format: "%.0fh/24h", min(gate.ageHours, 24)), done: gate.ageHours >= 24)
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func verificationButton(_ row: LedgerModel.ReviewRow) -> some View {
        if row.supports == 0 && row.contradicts == 0 {
            Button("검증 요청") { model.requestVerification(of: row.evidence) }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func establishedBadge(_ passed: Bool) -> some View {
        if passed {
            Text("확립 ★").font(.caption.bold())
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(.green.opacity(0.18), in: Capsule())
                .foregroundStyle(.green)
        }
    }

    private func gateItem(_ label: String, done: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(label).foregroundStyle(done ? .primary : .secondary)
        }
    }
}

/// 정제본 하나의 사람 심사 카드 — 루브릭(축별 0~5) + 코멘트 + 수락(확립)/반려.
/// 초기 점수는 distiller 자가채점을 제안값으로 채운다(사람이 보정).
struct DigestReviewRow: View {
    @Bindable var model: LedgerModel
    let digest: LedgerDocument

    @State private var scores: [String: Int] = [:]
    @State private var comment = ""
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
                    Text(digest.title).fontWeight(.medium).lineLimit(1).frame(minWidth: 0)
                    Spacer()
                    if let avg = ReviewVerdict(decision: .accept, scores: scores).averageScore, !scores.isEmpty {
                        Text(String(format: "%.1f", avg)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }.buttonStyle(.plain)

            if expanded {
                Text(digest.head.body).font(.callout).textSelection(.enabled)
                    .frame(maxHeight: 220).fixedSize(horizontal: false, vertical: true)
                Divider()
                ForEach(ReviewVerdict.axes, id: \.self) { axis in
                    HStack(spacing: 10) {
                        Text(axis).font(.caption).frame(width: 60, alignment: .leading)
                        ForEach(0...5, id: \.self) { n in
                            Button {
                                scores[axis] = n
                            } label: {
                                Image(systemName: (scores[axis] ?? -1) >= n && n > 0 ? "star.fill"
                                      : n == 0 ? "circle.slash" : "star")
                                    .font(.caption)
                                    .foregroundStyle((scores[axis] ?? -1) >= n && n > 0 ? NamuTheme.brand : .secondary)
                            }.buttonStyle(.plain)
                        }
                        axisScoreLabel(scores[axis])
                    }
                }
                TextField("코멘트 — 무엇이 좋았고/부족한가 (반려 시 distiller 세대 진화의 학습 신호)",
                          text: $comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...5).frame(minWidth: 0)
                HStack {
                    Button {
                        model.acceptDigest(digest, scores: scores, comment: comment)
                    } label: { Label("수락 · 위키 확립", systemImage: "checkmark.seal.fill") }
                        .tint(.green)
                    Button {
                        model.rejectDigest(digest, scores: scores, comment: comment)
                    } label: { Label("반려", systemImage: "arrow.uturn.left") }
                        .tint(.orange)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { if scores.isEmpty { scores = model.selfRubric(of: digest) } }
    }

    @ViewBuilder
    private func axisScoreLabel(_ score: Int?) -> some View {
        if let score {
            Text("\(score)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
