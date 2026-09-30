import KnowledgeBaseWikiCore
import SwiftUI

// 위키 마크다운 렌더 엔진 — 블록 파서 + MarkdownBody. (뷰는 WikiReaderView.swift)

enum WikiBlock: Identifiable {
    case heading(level: Int, text: String, number: String, anchor: String)
    case bullet(String)
    case code(String)
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case infobox(title: String, pairs: [(String, String)])
    case image(sha: String, caption: String)
    case paragraph(String)
    var id: String {
        switch self {
        case .heading(_, _, _, let a): return "h-" + a
        case .bullet(let t): return "b-" + t.prefix(24)
        case .code(let t): return "c-" + t.prefix(24)
        case .quote(let t): return "q-" + t.prefix(24)
        case .table(let h, _): return "t-" + h.joined().prefix(24)
        case .infobox(let t, _): return "i-" + t
        case .image(let sha, _): return "img-" + sha.prefix(12)
        case .paragraph(let t): return "p-" + t.prefix(24)
        }
    }
}

/// 본문 맨 앞 "개정 사유:" 줄은 역사 탭 소관 — 문서 본문에서 벗긴다.
func strippedWikiBody(_ body: String) -> String {
    var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let first = lines.first, first.hasPrefix("개정 사유:") {
        lines.removeFirst()
        while let head = lines.first, head.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
    }
    return lines.joined(separator: "\n")
}

/// 각주 정의 (`[^n]: 내용`) 를 본문에서 분리.
func extractFootnotes(_ text: String) -> (body: String, notes: [(String, String)]) {
    var notes: [(String, String)] = []
    var bodyLines: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if let match = line.range(of: #"^\[\^([^\]]+)\]:\s*"#, options: .regularExpression) {
            let id = String(line[line.index(line.startIndex, offsetBy: 2)..<(line.firstIndex(of: "]") ?? line.endIndex)])
            notes.append((id, String(line[match.upperBound...])))
        } else {
            bodyLines.append(line)
        }
    }
    return (bodyLines.joined(separator: "\n"), notes)
}

func wikiBlocks(from text: String) -> [WikiBlock] {
    var result: [WikiBlock] = []
    var inCode = false
    var codeLines: [String] = []
    var counters = [0, 0, 0]
    var headingIndex = 0
    var tableBuffer: [[String]] = []
    var infoboxTitle: String?
    var infoboxPairs: [(String, String)] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    func flushTable() {
        guard !tableBuffer.isEmpty else { return }
        // 2번째 행이 구분선(---)이면 제거
        var rows = tableBuffer
        let headers = rows.removeFirst()
        if let sep = rows.first, sep.allSatisfy({ $0.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces).isEmpty }) {
            rows.removeFirst()
        }
        result.append(.table(headers: headers, rows: rows))
        tableBuffer = []
    }

    for rawLine in lines {
        let line = rawLine
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // 정보상자 펜스
        if trimmed.hasPrefix(":::") {
            if infoboxTitle != nil {
                result.append(.infobox(title: infoboxTitle!, pairs: infoboxPairs))
                infoboxTitle = nil; infoboxPairs = []
            } else {
                infoboxTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if infoboxTitle!.isEmpty { infoboxTitle = "정보" }
            }
            continue
        }
        if infoboxTitle != nil {
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { infoboxPairs.append((parts[0], parts[1])) }
            continue
        }
        if trimmed.hasPrefix("```") {
            if inCode { result.append(.code(codeLines.joined(separator: "\n"))); codeLines = [] }
            inCode.toggle(); continue
        }
        if inCode { codeLines.append(line); continue }
        // 표 (파이프 행 연속)
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1 {
            let cells = trimmed.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            tableBuffer.append(cells); continue
        } else { flushTable() }
        if trimmed.isEmpty { continue }
        // 이미지: ![캡션](blob:<sha>)  또는  레거시 [그림 blob: <sha>]
        if let m = trimmed.range(of: #"^!\[([^\]]*)\]\(blob:([a-f0-9]{64})\)$"#, options: .regularExpression) {
            let inner = String(trimmed[m])
            let sha = inner.range(of: #"[a-f0-9]{64}"#, options: .regularExpression).map { String(inner[$0]) } ?? ""
            let cap = inner.range(of: #"(?<=\!\[)[^\]]*"#, options: .regularExpression).map { String(inner[$0]) } ?? ""
            result.append(.image(sha: sha, caption: cap)); continue
        }
        if let m = trimmed.range(of: #"^\[그림 blob:\s*([a-f0-9]{64})\]$"#, options: .regularExpression) {
            let sha = String(trimmed[m]).range(of: #"[a-f0-9]{64}"#, options: .regularExpression).map { String(String(trimmed[m])[$0]) } ?? ""
            result.append(.image(sha: sha, caption: "")); continue
        }
        if trimmed.range(of: #"^\[\^[^\]]+\]:"#, options: .regularExpression) != nil { continue }
        if trimmed.hasPrefix("> ") { result.append(.quote(String(trimmed.dropFirst(2)))); continue }
        func heading(_ level: Int, _ title: String) {
            counters[level - 1] += 1
            for deeper in level..<3 { counters[deeper] = 0 }
            let number = counters.prefix(level).filter { $0 > 0 }.map(String.init).joined(separator: ".")
            result.append(.heading(level: level, text: title, number: number, anchor: "sec-\(headingIndex)"))
            headingIndex += 1
        }
        if trimmed.hasPrefix("### ") { heading(3, String(trimmed.dropFirst(4))) }
        else if trimmed.hasPrefix("## ") { heading(2, String(trimmed.dropFirst(3))) }
        else if trimmed.hasPrefix("# ") { heading(1, String(trimmed.dropFirst(2))) }
        else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { result.append(.bullet(String(trimmed.dropFirst(2)))) }
        else { result.append(.paragraph(trimmed)) }
    }
    flushTable()
    if let title = infoboxTitle { result.append(.infobox(title: title, pairs: infoboxPairs)) }
    if inCode, !codeLines.isEmpty { result.append(.code(codeLines.joined(separator: "\n"))) }
    return result
}

struct MarkdownBody: View {
    let text: String
    var linkExists: ((String) -> Bool)? = nil
    var suppressInfobox = false
    var blobImage: ((String) -> Data?)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(wikiBlocks(from: text)) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: WikiBlock) -> some View {
        switch block {
        case .heading(let level, let text, let number, let anchor):
            let font: Font = level == 1 ? .title.weight(.semibold)
                : level == 2 ? .title2.weight(.semibold) : .headline
            (Text(number + ". ").foregroundStyle(.secondary) + inline(text))
                .font(font)
                .padding(.top, level == 1 ? 8 : level == 2 ? 6 : 4)
                .id(anchor)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(.teal.opacity(0.5)).frame(width: 3)
                inline(text).italic().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, header: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    tableRow(row, header: false)
                }
            }
            .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        case .infobox(let title, let pairs):
            if suppressInfobox { EmptyView() } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(.teal.opacity(0.15))
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 8) {
                        Text(pair.0).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        inline(pair.1).font(.callout)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: 300)
            .background(.background)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.teal.opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        case .image(let sha, let caption):
            VStack(alignment: .leading, spacing: 4) {
                if let data = blobImage?(sha), let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    if !caption.isEmpty {
                        inline(caption).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    // blob 미보유(대용량 제외 등) — 참조만 표시
                    Label(caption.isEmpty ? "그림 \(sha.prefix(12))…" : caption, systemImage: "photo")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        case .paragraph(let text):
            inline(text)
        }
    }

    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                inline(cell)
                    .font(header ? .callout.weight(.semibold) : .callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
        .background(header ? AnyShapeStyle(.teal.opacity(0.1)) : AnyShapeStyle(.clear))
    }

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    /// 정규식 매치를 그룹 기반으로 치환 (역순 적용 — 인덱스 안정).
    static func replaceMatches(_ text: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            let replacement = transform(groups)
            let full = match.range(at: 0)
            result = (result as NSString).replacingCharacters(in: full, with: replacement)
        }
        return result
    }

    /// 인라인: [[내부링크]], [^각주], 강조를 처리해 Text 로.
    private func inline(_ raw: String) -> Text {
        var text = raw
        var trailingMarker: Text?
        let epistemics: [(String, Color)] = [("〔발췌〕", .secondary), ("〔추론〕", .orange), ("〔불확실〕", .red)]
        for (tag, color) in epistemics where text.contains(tag) {
            text = text.replacingOccurrences(of: tag, with: "").trimmingCharacters(in: .whitespaces)
            trailingMarker = Text(" \(tag)").font(.caption2).foregroundStyle(color)
        }
        // [[제목]] / [[제목|표시]] → 인코딩된 커스텀 스킴 링크 (공백·한글 안전)
        text = Self.replaceMatches(text, pattern: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#) { g in
            "[\(g[2])](memoledger://wiki/\(Self.encode(g[1])))"
        }
        text = Self.replaceMatches(text, pattern: #"\[\[([^\]]+)\]\]"#) { g in
            "[\(g[1])](memoledger://wiki/\(Self.encode(g[1])))"
        }
        // [^n] → [n] 링크 (나무위키식 각주 표기)
        text = Self.replaceMatches(text, pattern: #"\[\^([^\]]+)\]"#) { g in
            "[\\[\(g[1])\\]](memoledger://footnote/\(Self.encode(g[1])))"
        }
        let main: Text
        if var attributed = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            if let linkExists {
                for run in attributed.runs {
                    guard let url = run.link, url.scheme == "memoledger", url.host == "wiki" else { continue }
                    let title = (url.path.replacingOccurrences(of: "/", with: "").removingPercentEncoding) ?? ""
                    if !title.isEmpty {
                        // 나무위키식: 있으면 파랑 내부링크, 없으면 빨간링크
                        attributed[run.range].foregroundColor = linkExists(title) ? NamuTheme.internalLink : NamuTheme.redLink
                    }
                }
            }
            main = Text(attributed)
        } else {
            main = Text(text)
        }
        return trailingMarker.map { main + $0 } ?? main
    }
}

/// 위키 섹션 블록 — 마우스 올리면 [편집]·[이의] 노출 (나무위키 섹션 파편화).
