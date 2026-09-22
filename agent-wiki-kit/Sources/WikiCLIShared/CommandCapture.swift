import Foundation
import KnowledgeBaseWikiCore

public func runCapture(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    // 텍스트 수집 — URL 없는 원문(유튜브 스크립트 등)을 stdin/--file 로 받아 blob 봉인 후 수집함으로.
    if arguments[1] == "--text" || arguments[1] == "--file" {
        runCaptureText(store: store, author: author, arguments: arguments); return
    }
    let urlString = arguments[1]
    guard urlString.hasPrefix("http") else {
        fail("http(s) URL, 또는 URL 없는 원문은 `capture --text` (stdin) / `capture --file <경로>`")
    }
    var captureTitle = urlString
    if let index = arguments.firstIndex(of: "--title"), arguments.count > index + 1 {
        captureTitle = arguments[index + 1]
    }
    let excerpt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    do {
        let object = try store.publish(author: author, title: "근거: \(captureTitle)", body: excerpt.isEmpty ? "(발췌 없음 — 원문은 origin 참조)" : excerpt, extras: LedgerPublishExtras(origin: urlString))
        print("수집함으로: \(object.id.prefix(8))  — 앱 수집함에서 선별을 기다립니다") // allow:debug
        // 원본 provenance — 수집 원문을 blob 으로 봉인하고 fetch 사건을 남긴다(researcher 트리오).
        // 사건은 진행 중 작업(MEMO_LEDGER_RUN, runEngine 이 주입)에 단계로 매단다.
        let log = EventLog(root: store.root)
        var sha: String?
        if !excerpt.isEmpty {
            do { sha = try BlobStore(root: store.root).put(Data(excerpt.utf8)) }
            catch { fputs("warn: blob put: \(error)\n", stderr) }
        }
        let captureExtras = Event.Extras(
            object: urlString, source: sha,
            parent: ProcessInfo.processInfo.environment["MEMO_LEDGER_RUN"])
        do { try log.append(Event(
            writer: author, subject: object.id, rel: "웹 수집",
            level: .step, extras: captureExtras))
        } catch { fputs("warn: event log: \(error)\n", stderr) }
    } catch {
        fail("\(error)")
    }
}

/// 텍스트 원문 수집 — 위키에 바로 안 넣는다. 원문을 blob 으로 불변 봉인하고, 그 원문을
/// 인용하는 근거 객체를 수집함(트리아지 대기)으로 발행한다. 이후 distiller 가 정제 → 심사대.
public func runCaptureText(store: LedgerStore, author: String, arguments: [String]) {
    func flag(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
        return arguments[i + 1]
    }
    var title = flag("--title") ?? "원문"
    let project = flag("--project")          // 프로젝트(그룹)
    let authoredOverride = flag("--authored") // 원문 작성일 수동 보정 (자동추출보다 우선)

    var text: String
    var kind: String
    var authoredAuto: String?
    var rawBytes: Data
    var sourcePath: String?
    if let path = flag("--file") {
        let abs = URL(fileURLWithPath: path).standardizedFileURL.path
        let ex = extractFromFile(abs, whisperModel: flag("--model"))
        text = ex.text; kind = ex.kind; authoredAuto = ex.authoredAt; rawBytes = ex.rawBytes
        sourcePath = abs
        if flag("--title") == nil { title = URL(fileURLWithPath: abs).lastPathComponent }  // 제목 기본값 = 파일명
    } else {
        text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        kind = "text"; rawBytes = Data(text.utf8)
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { fail("원문이 비어 있음 — stdin/--file 로 본문을, PDF 는 텍스트가 추출돼야 합니다") }
    do {
        // 원문 바이트를 그대로 불변 봉인 — 원본 층(PDF/오디오면 파일 원형, 텍스트면 본문).
        let sha = try BlobStore(root: store.root).put(rawBytes)
        let provenance = Provenance(
            kind: kind, path: sourcePath, project: project,
            authoredAt: authoredOverride ?? authoredAuto, blob: sha)
        // 수집함 판정은 origin 스킴(paste:)으로 — http 와 같은 '수집물(미선별)' 취급.
        let object = try store.publish(author: author, title: "근거: \(title)", type: "evidence", body: trimmed, extras: LedgerPublishExtras(origin: "paste:\(sha.prefix(12))", source: provenance))
        let meta = [kind, project.map { "프로젝트 \($0)" }, provenance.authoredAt.map { "작성 \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
        print("수집함으로: \(object.id.prefix(8))  (\(trimmed.count)자, blob \(sha.prefix(8))\(meta.isEmpty ? "" : ", \(meta)")) — distiller 정제 대기") // allow:debug
        let log = EventLog(root: store.root)
        try? log.append(Event(writer: author, subject: object.id, rel: "\(kind) 수집", level: .step, extras: Event.Extras(object: sourcePath ?? "paste:\(sha.prefix(12))", source: sha, parent: ProcessInfo.processInfo.environment["MEMO_LEDGER_RUN"])))
    } catch {
        fail("\(error)")
    }
}

