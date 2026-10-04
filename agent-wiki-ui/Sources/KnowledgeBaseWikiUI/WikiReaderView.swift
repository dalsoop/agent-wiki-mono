import KnowledgeBaseWikiCore
import SwiftUI

/// 위키 읽기 화면 — md 를 사람 읽는 타이포그래피로 렌더 + 인용 근거를 제목 칩으로.
enum WikiTab: String, CaseIterable { case document = "문서", discussion = "토론", history = "역사" }

/// 위키 읽기 화면 — 나무위키식: 분류·목차·[문서|토론|역사] 탭.
struct WikiReaderView: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    @State private var tab: WikiTab = .document

    private var headings: [WikiBlock] {
        wikiBlocks(from: document.head.body).filter {
            if case .heading = $0 { return true }; return false
        }
    }

    var body: some View {
        let discussions = model.discussions(of: document)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 제목 + 분류 줄 (나무위키 상단)
                    Text(document.title.replacingOccurrences(of: "개념: ", with: "")
                        .replacingOccurrences(of: "엔티티: ", with: ""))
                        .font(.largeTitle.weight(.bold))
                        // 나무위키식 제목 밑줄 (연초록 #d4f0e3)
                        .background(alignment: .bottom) {
                            NamuTheme.titleUnderline.frame(height: 10).offset(y: 2)
                        }
                    HStack(spacing: 6) {
                        Text("분류:").font(.caption).foregroundStyle(.tertiary)
                        ForEach(document.head.tags, id: \.self) { tag in
                            Button { model.area = .evidence; model.evidenceTagFilter = tag } label: {
                                Text(tag).font(.caption)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(NamuTheme.brand.opacity(0.12), in: Capsule())
                                    .foregroundStyle(NamuTheme.brand)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                        Text("판 \(document.versions.count) · \(document.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    // 탭
                    Picker("", selection: $tab) {
                        ForEach(WikiTab.allCases, id: \.self) { item in
                            Text(item == .discussion ? "토론 (\(discussions.count))"
                                 : item == .history ? "역사 (\(document.versions.count))" : item.rawValue)
                                .tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Divider()

                    switch tab {
                    case .document:
                        WikiDocumentTab(model: model, document: document, headings: headings, proxy: proxy)
                    case .discussion:
                        WikiDiscussionSection(model: model, document: document)
                    case .history:
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(document.versions, id: \.id) { version in
                                RevisionRow(model: model, version: version,
                                            isHead: version.id == document.head.id)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1040, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "memoledger" else { return .systemAction }
                let target = (url.path.replacingOccurrences(of: "/", with: "")
                    .removingPercentEncoding) ?? ""
                switch url.host {
                case "wiki":                                  // [[내부링크]] → 문서 점프
                    if !target.isEmpty { model.jumpToTitle(target) }
                case "footnote":                              // [^n] → 하단 각주로 스크롤
                    withAnimation { proxy.scrollTo("fn-\(target)", anchor: .center) }
                default: break
                }
                return .handled
            })
        }
    }
}

/// 문서 탭 — 상단 이동 통 + 2열(좌 본문 / 우 정보상자, 좁으면 1열 스택). openNAMU 반응형 판단 이식.
struct WikiDocumentTab: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    let headings: [WikiBlock]
    let proxy: ScrollViewProxy

    @State private var width: CGFloat = 0

    var body: some View {
        let infobox = model.extractInfobox(strippedWikiBody(document.head.body)).box
        // 명시적 전환점(openNAMU @420 원리): 넓으면 2열(정보상자 우측), 좁으면 1열(정보상자 상단)
        let twoColumn = width >= 640
        VStack(alignment: .leading, spacing: 12) {
            topNav
            if twoColumn {
                HStack(alignment: .top, spacing: 16) {
                    mainColumn
                    if let infobox { InfoboxView(box: infobox, model: model).frame(width: 260) }
                }
            } else {
                if let infobox { InfoboxView(box: infobox, model: model).frame(maxWidth: 320, alignment: .leading) }
                mainColumn
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder private var topNav: some View {
        let sibs = model.siblingWikiPages(of: document)
        if !sibs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sibs) { doc in
                        Button { model.jump(toObject: doc.id) } label: {
                            Text(doc.title.replacingOccurrences(of: "개념: ", with: "")
                                .replacingOccurrences(of: "엔티티: ", with: ""))
                                .font(.caption).lineLimit(1).frame(minWidth: 0)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(NamuTheme.brand.opacity(0.12), in: Capsule())
                                .foregroundStyle(NamuTheme.brand)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
            .background(NamuTheme.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) { NamuTheme.navGradient.frame(width: 3).clipShape(Capsule()) }
        }
    }

    @ViewBuilder private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if headings.count > 1 { tableOfContents }
            let split = extractFootnotes(strippedWikiBody(document.head.body))
            ForEach(model.wikiSections(document.head.body)) { section in
                WikiSectionBlock(model: model, document: document, section: section)
            }
            if !split.notes.isEmpty {
                Divider()
                Text("각주").font(.headline)
                ForEach(Array(split.notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 6) {
                        Text("[\(note.0)]").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        MarkdownBody(text: note.1).font(.callout)
                    }
                    .id("fn-\(note.0)")
                }
            }
            // 선행 플레이북(의존성) — requires 로 인용한 것. 먼저 완료해야 하는 절차.
            let requires = document.head.cites.filter { $0.rel == "requires" }
            if !requires.isEmpty {
                Divider()
                Text("선행 플레이북 \(requires.count) — 먼저 완료(requires)").font(.headline)
                ForEach(requires, id: \.id) { cite in
                    Button { model.jump(toObject: cite.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.left.up").foregroundStyle(.orange)
                            Text((model.objectsByID[cite.id]?.title ?? String(cite.id.prefix(8)))
                                .replacingOccurrences(of: "플레이북: ", with: ""))
                                .font(.callout).lineLimit(1).frame(minWidth: 0)
                        }
                    }.buttonStyle(.plain)
                }
            }
            // 후행 플레이북 — 이 플레이북을 requires 로 인용하는 것(이 절차에 의존).
            if document.head.effectiveType == "playbook" {
                let dependents = model.playbookDependents(ofLineage: Set(document.versions.map(\.id)))
                if !dependents.isEmpty {
                    Divider()
                    Text("이 플레이북을 필요로 함 \(dependents.count)").font(.headline)
                    ForEach(dependents) { d in
                        Button { model.jump(toObject: d.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.right.down").foregroundStyle(.blue)
                                Text((d.title ?? "").replacingOccurrences(of: "플레이북: ", with: "")).font(.callout).lineLimit(1).frame(minWidth: 0)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            let cites = document.head.cites.filter { $0.rel != "checkpoints" && $0.rel != "requires" }
            if !cites.isEmpty {
                Divider()
                Text("이 페이지가 인용한 근거 \(cites.count)").font(.headline)
                FlowChips(items: cites.map { cite in
                    (id: cite.id,
                     label: (model.objectsByID[cite.id]?.title ?? String(cite.id.prefix(8)))
                        .replacingOccurrences(of: "근거: ", with: ""))
                }) { id in model.jump(toObject: id) }
            }
            // 플레이북 템플릿이면 실행 표본(데이터셋)을 아래에 나열 — 같은 방법 반복 여부를 표본으로.
            if document.head.effectiveType == "playbook" {
                let runs = model.playbookRuns(ofLineage: Set(document.versions.map(\.id)))
                if !runs.isEmpty {
                    Divider()
                    Text("실행 표본 \(runs.count) — 같은 방법 반복 기록").font(.headline)
                    ForEach(runs) { run in
                        Button { model.jump(toObject: run.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle").foregroundStyle(.green)
                                Text((run.title ?? "실행").replacingOccurrences(of: "플레이북 실행: ", with: ""))
                                    .font(.callout).lineLimit(1).frame(minWidth: 0)
                                Spacer()
                                Text(run.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var tableOfContents: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("목차").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(headings) { block in
                if case let .heading(level, text, number, anchor) = block {
                    Button { withAnimation { proxy.scrollTo(anchor, anchor: .top) } } label: {
                        HStack(spacing: 4) {
                            Text(number + ".").foregroundStyle(.secondary)
                            Text(text)
                        }
                        .font(.callout)
                        .padding(.leading, CGFloat(level - 1) * 14)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 판 하나의 행 — 개정 사유(본문 첫 줄) + 사고과정(같은 batch 의 run/대화기록) 링크.
struct RevisionRow: View {
    @Bindable var model: LedgerModel
    let version: LedgerObject
    let isHead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isHead ? "largecircle.fill.circle" : "circle")
                    .font(.caption).foregroundStyle(isHead ? Color.accentColor : .secondary)
                Text(version.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(version.author).font(.caption.weight(.medium))
                if isHead { Text("현재 판").font(.caption2).foregroundStyle(.tertiary) }
            }
            Text(revisionReason)
                .font(.callout).foregroundStyle(.secondary)
                .padding(.leading, 20)
            if let record = model.conversationRecord(batch: version.batch) {
                Button {
                    model.jump(toObject: record.head.id)
                } label: {
                    Label("이 개정의 사고과정 (대화기록)", systemImage: "text.bubble")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .padding(.leading, 20)
            }
        }
    }

    private var revisionReason: String {
        let first = version.body.split(separator: "\n").first.map(String.init) ?? ""
        return first.hasPrefix("개정 사유:") ? first : (isHead ? "(사유 미기재)" : "초판 또는 사유 미기재")
    }
}

/// 위키 토론 — 이의·질문·수정요청 스레드와 그 자리 작성기.
struct WikiDiscussionSection: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    @State private var kind: LedgerModel.DiscussionKind = .question
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let discussions = model.discussions(of: document)
            Text("토론 (\(discussions.count))").font(.headline)
            ForEach(discussions) { discussion in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text((discussion.title ?? "").split(separator: ":").first.map(String.init) ?? "토론")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((discussion.effectiveType == "objection" ? Color.red : .blue).opacity(0.12), in: Capsule())
                            .foregroundStyle(discussion.effectiveType == "objection" ? Color.red : .blue)
                        Text(discussion.author).font(.caption).foregroundStyle(.secondary)
                        Text(discussion.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(discussion.body).font(.callout)
                    ForEach(model.responses(to: discussion)) { response in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                            Button {
                                model.jump(toObject: response.id)
                            } label: {
                                Text("\(response.author): \(response.title ?? String(response.body.prefix(60)))")
                                    .font(.caption).lineLimit(1).frame(minWidth: 0)
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.leading, 12)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Picker("", selection: $kind) {
                    ForEach(LedgerModel.DiscussionKind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented).frame(width: 220)
                TextField("이 페이지에 대해 사서에게…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("발행") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    model.postDiscussion(on: document, kind: kind, text: text)
                    draft = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(kind == .objection
                 ? "이의는 undercuts 인용으로 발행 — 페이지 신뢰도에 반영되고 사서가 다음 루프에서 처리"
                 : "발행 즉시 사서(wiki-maintainer)가 기동해 답변·개정으로 응답합니다 (응답은 이 스레드에 연결)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// 경량 md 렌더러 — 헤딩·불릿·코드블록·인라인 강조. (외부 의존성 없음)
/// md 블록 (헤딩은 번호·앵커 포함). MarkdownBody 와 목차가 같은 파서를 쓴다.
struct WikiSectionBlock: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    let section: LedgerModel.WikiSection
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @State private var reason = ""
    @State private var arguing = false
    @State private var objection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let _ = section.heading {
                        let font: Font = section.level == 1 ? .title.weight(.semibold)
                            : section.level == 2 ? .title2.weight(.semibold) : .headline
                        // 나무위키식 섹션 헤딩 — 하단 경계선(#ccc)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(section.number). \(section.headingText)").font(font)
                            Rectangle().fill(NamuTheme.headingBorder).frame(height: 1)
                        }
                        .id(section.anchor)
                    }
                    if !section.bodyWithoutHeading.isEmpty {
                        MarkdownBody(text: model.expandIncludes(section.bodyWithoutHeading), linkExists: model.wikiLinkExists, suppressInfobox: true, blobImage: model.blobData)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hovering && !editing {
                    HStack(spacing: 8) {
                        if !model.isReadOnlyWorld {  // 보관된 원장(전신)은 편집 버튼을 숨긴다
                            Button("편집") { draft = section.raw; reason = ""; editing = true }
                        }
                        Button("이의") { objection = ""; arguing = true }
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.teal)
                }
            }
            if editing {
                TextEditor(text: $draft)
                    .font(.system(.callout, design: .monospaced)).frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    TextField("편집 사유 (원장에 남습니다)", text: $reason).textFieldStyle(.roundedBorder)
                    Button("취소") { editing = false }
                    Button("저장") {
                        model.editWikiSection(document, index: section.index, newRaw: draft,
                                              reason: reason.isEmpty ? "섹션 편집" : reason)
                        editing = false
                    }.buttonStyle(.borderedProminent)
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if arguing {
                HStack {
                    TextField("이 섹션에 이의…", text: $objection, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("취소") { arguing = false }
                    Button("이의 발행") {
                        let head = section.heading?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) ?? "서문"
                        model.postDiscussion(on: document, kind: .objection, text: "[섹션: \(head)] " + objection)
                        arguing = false
                    }.buttonStyle(.borderedProminent)
                        .disabled(objection.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, hovering ? 8 : 0)
        .background((hovering ? Color.teal.opacity(0.05) : .clear), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}

struct InfoboxView: View {
    let box: LedgerModel.Infobox
    @Bindable var model: LedgerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(box.title).font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(.teal.opacity(0.15))
            if let image = box.image {
                Group {
                    if image.hasPrefix("sf:") {
                        Image(systemName: String(image.dropFirst(3)))
                            .font(.system(size: 44)).foregroundStyle(.teal)
                    } else {
                        Text(image).font(.system(size: 44))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            ForEach(Array(box.pairs.enumerated()), id: \.offset) { _, pair in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.0).font(.caption2).foregroundStyle(.secondary)
                    MarkdownBody(text: pair.1, linkExists: model.wikiLinkExists).font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                Divider()
            }
        }
        .padding(.bottom, 6)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.teal.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FlowChips: View {
    let items: [(id: String, label: String)]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button {
                    onTap(item.id)
                } label: {
                    Text(item.label)
                        .font(.caption).lineLimit(1).frame(minWidth: 0)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
