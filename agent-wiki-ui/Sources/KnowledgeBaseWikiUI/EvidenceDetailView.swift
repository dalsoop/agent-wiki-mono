import Charts
import KnowledgeBaseWikiCore
import SwiftUI

/// 근거 상세 — 읽기 전용 본문 + 생애 타임라인(감쇠 곡선 + 재현·반박 이벤트) + 액션.
struct EvidenceDetailView: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument
    @State private var showReinforce = false
    @State private var reinforceContradicts = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                EvidenceDetailHeader(model: model, document: document)
                EvidenceDetailClassifiers(model: model, document: document)
                if let retraction = model.retraction(of: document) {
                    EvidenceRetractionBanner(retraction: retraction)
                }
                EvidenceDetailMeta(model: model, document: document)
                AuthoringPanel(authoring: document.head.authoring)
                EvidenceOriginBlock(document: document)
                if let source = document.head.source {
                    EvidenceSourceProvenance(source: source) { blob in
                        model.openBlobExternally(blob)
                    }
                }
                EvidenceLifeTimeline(model: model, document: document)
                Divider()
                Text(document.head.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                EvidenceCitationList(model: model, document: document)
                EvidenceClassificationLog(model: model, document: document)
                EvidenceReinforcementLog(model: model, document: document)
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    reinforceContradicts = false
                    showReinforce = true
                } label: {
                    Label("재현 확인", systemImage: "checkmark.seal")
                }
                Button {
                    reinforceContradicts = true
                    showReinforce = true
                } label: {
                    Label("반박", systemImage: "bolt")
                }
            }
        }
        .sheet(isPresented: $showReinforce) {
            ReinforceSheet(model: model, document: document, contradicts: reinforceContradicts)
        }
    }
}

private struct EvidenceDetailHeader: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        HStack(spacing: 8) {
            Text(document.title.replacingOccurrences(of: "근거: ", with: ""))
                .font(.title2.weight(.semibold))
            if let strength = model.strength(of: document) {
                StrengthGauge(score: strength.score)
            }
        }
    }
}

private struct EvidenceDetailClassifiers: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        HStack(spacing: 6) {
            if let domain = model.domainByDocument[document.id] {
                classifierChip(domain, color: .teal)
            }
            if let kind = model.kindByDocument[document.id] {
                classifierChip(kind, color: .secondary)
            }
            if let knowledge = model.knowledgeByDocument[document.id] {
                classifierChip(knowledgeDisplay(knowledge), color: knowledgeTint(knowledge))
            }
            ForEach(document.head.tags, id: \.self) { tag in
                Text("#" + tag).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct EvidenceRetractionBanner: View {
    let retraction: LedgerObject

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                "폐기됨 — \(retraction.author) · \(retraction.published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())",
                systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red).font(.callout.weight(.semibold))
            Text(retraction.body).font(.callout).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EvidenceDetailMeta: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        HStack(spacing: 6) {
            StageBadge(stage: model.stage(of: document.head))
            Text("\(document.head.author == "human" ? "내가" : document.head.author) 발행 · \(document.head.published, format: .dateTime) · 발행 후 수정 불가")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct EvidenceOriginBlock: View {
    let document: LedgerDocument

    var body: some View {
        if let origin = document.head.origin, origin.hasPrefix("memo-vault:") {
            Label(
                "작업면에서 확정되어 넘어옴: \(origin.dropFirst("memo-vault:".count))",
                systemImage: "arrow.right.doc.on.clipboard")
                .font(.caption).foregroundStyle(.blue)
        } else if let origin = document.head.origin,
                  !(origin.hasPrefix("paste:") && document.head.source != nil) {
            EvidenceOriginCaption(origin: origin)
        }
    }
}

private struct EvidenceOriginCaption: View {
    let origin: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link").font(.caption)
            if origin.hasPrefix("http"), let url = URL(string: origin) {
                Link(origin, destination: url).font(.caption)
            } else {
                Text("출처: \(origin)").font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EvidenceSourceProvenance: View {
    let source: Provenance
    let openBlob: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: kindIcon).font(.caption)
                if let kind = source.kind {
                    Text(kind.uppercased()).font(.caption2.weight(.semibold))
                }
                if let project = source.project {
                    Text(project).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(NamuTheme.brand.opacity(0.15), in: Capsule())
                }
                if let authored = source.authoredAt {
                    Label(authored, systemImage: "calendar").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let path = source.path {
                Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            if let blob = source.blob {
                Button {
                    openBlob(blob)
                } label: {
                    Label("원본 열기 (\(blob.prefix(8)))", systemImage: "doc.badge.arrow.up")
                        .font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(NamuTheme.brand)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var kindIcon: String {
        switch source.kind {
        case "pdf": return "doc.richtext"
        case "audio": return "waveform"
        case "image": return "photo"
        case "web": return "globe"
        default: return "text.alignleft"
        }
    }
}

private struct EvidenceLifeTimeline: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        let events = model.lifeEvents(of: document)
        let now = Date()
        Chart {
            if let strength = model.strength(of: document) {
                let start = strength.lastReinforcedAt
                ForEach(0..<24, id: \.self) { step in
                    let t = start.addingTimeInterval(now.timeIntervalSince(start) * Double(step) / 23)
                    let days = t.timeIntervalSince(start) / 86_400
                    LineMark(
                        x: .value("시각", t),
                        y: .value("신선도", pow(0.5, days / EvidenceStrength.halfLifeDays)))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            ForEach(events) { event in
                PointMark(x: .value("시각", event.date), y: .value("신선도", 1.05))
                    .foregroundStyle(color(for: event.kind))
                    .symbolSize(event.kind == "published" ? 90 : 60)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1.15)
        .frame(height: 72)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Label("발행", systemImage: "circle.fill").foregroundStyle(.blue)
                Label("재현", systemImage: "circle.fill").foregroundStyle(.green)
                Label("반박", systemImage: "circle.fill").foregroundStyle(.red)
            }
            .font(.caption2).labelStyle(.titleAndIcon)
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "supports": return .green
        case "contradicts": return .red
        case "revised": return .gray
        default: return .blue
        }
    }
}

private struct EvidenceCitationList: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        let references = model.references(to: document)
        if !references.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("이 근거를 인용한 기록").font(.headline)
                ForEach(references) { reference in
                    Button(reference.title) {
                        model.area = .myNotes
                        model.select(reference)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

private struct EvidenceClassificationLog: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        let stamps = model.classifications(of: document)
        if !stamps.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("분류 기록").font(.headline)
                ForEach(stamps) { stamp in
                    EvidenceStampCard(
                        bodyText: stamp.body,
                        author: stamp.author,
                        published: stamp.published,
                        conversation: model.conversationRecord(batch: stamp.batch)
                    ) { conversation in
                        model.selectedDocumentID = conversation.id
                    }
                }
            }
        }
    }
}

private struct EvidenceReinforcementLog: View {
    @Bindable var model: LedgerModel
    let document: LedgerDocument

    var body: some View {
        let rows = model.reinforcements(of: document)
        if !rows.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("재현·반박 내역").font(.headline)
                ForEach(rows, id: \.object.id) { row in
                    EvidenceReinforcementRow(
                        row: row,
                        conversation: model.conversationRecord(batch: row.object.batch)
                    ) { conversation in
                        model.area = .evidence
                        model.selectedDocumentID = conversation.id
                    }
                }
            }
        }
    }
}

private struct EvidenceReinforcementRow: View {
    let row: (object: LedgerObject, rel: String)
    let conversation: LedgerDocument?
    let onOpen: (LedgerDocument) -> Void

    var body: some View {
        let contradicts = EvidenceStrength.contradictRels.contains(row.rel)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: contradicts ? "bolt.fill" : "checkmark.seal.fill")
                .foregroundStyle(contradicts ? Color.red : Color.green)
                .font(.caption)
            EvidenceStampCard(
                bodyText: row.object.body.split(separator: "\n").first.map(String.init) ?? "",
                author: row.object.author == "human" ? "나" : row.object.author,
                published: row.object.published,
                conversation: conversation,
                onOpen: onOpen)
        }
    }
}

private struct EvidenceStampCard: View {
    let bodyText: String
    let author: String
    let published: Date
    let conversation: LedgerDocument?
    var onOpen: (LedgerDocument) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bodyText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text("\(author) · \(published, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())")
                    .font(.caption).foregroundStyle(.secondary)
                if let conversation {
                    Button("대화기록") { onOpen(conversation) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}
