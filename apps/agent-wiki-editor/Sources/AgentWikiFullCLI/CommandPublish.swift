import CommandKit
import EndpointRouterKit
import Foundation
import InteropKit
import KnowledgeBaseWikiCore
import LocalizationKit
import PDFKit
import StateRootKit

/// 파일 → 텍스트 추출 결과. 원본 바이트는 그대로 봉인하고, 여기서 뽑은 텍스트를 수집물 본문으로 쓴다.
private struct Extracted {
    var text: String
    var kind: String        // pdf | text | image | audio
    var authoredAt: String? // 원문 작성일(자동 추출) — ISO yyyy-MM-dd
    var rawBytes: Data      // 원본 바이트(불변 봉인 대상)
}

private func isoDay(_ date: Date?) -> String? {
    guard let date else { return nil }
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

private func fileModifiedDay(_ path: String) -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let mtime = attrs[.modificationDate] as? Date else { return nil }
    return isoDay(mtime)
}

/// 외부 명령 동기 실행 — (exit code, stdout+stderr). CommandKit 워치독 포함.
private func runTool(_ launch: String, _ args: [String], timeout: TimeInterval = 1800) -> (code: Int32, out: String) {
    let result = CommandKitSync.run(launch, args, timeout: timeout)
    return (result.exitCode, result.stdout + result.stderr)
}

private func firstExisting(_ paths: [String]) -> String? {
    paths.first { FileManager.default.fileExists(atPath: $0) }
}

/// whisper.cpp 모델 경로 해석 — override → 환경변수 → 흔한 위치. 없으면 nil.
private func resolveWhisperModel(_ override: String?) -> String? {
    if let override, FileManager.default.fileExists(atPath: override) { return override }
    if let env = ProcessInfo.processInfo.environment["MEMO_WHISPER_MODEL"],
       FileManager.default.fileExists(atPath: env) { return env }
    let home = StateRootKit.root
    let candidates = [
        "\(home)/.cache/whisper/ggml-large-v3.bin",
        "\(home)/.cache/whisper/ggml-medium.bin",
        "\(home)/.cache/whisper/ggml-base.bin",
        "\(home)/Library/Application Support/whisper/ggml-base.bin",
        "\(home)/models/ggml-base.bin",
        "\(HostPlatform.homebrewPrefix)/share/whisper-cpp/ggml-base.bin",
    ]
    // for-tests-ggml-tiny 는 유닛테스트용 더미(빈 전사)라 폴백에서 제외한다 — 실모델만 쓴다.
    return firstExisting(candidates)
}

/// 원격 whisper 서버 URL — 환경변수 override, 없으면 gujo 50서버(faster-whisper-large-v3, OpenAI 호환).
/// health(GET /health)가 200 이면 쓸 수 있다고 본다.
private func remoteWhisperURL() -> String? {
    let env = ProcessInfo.processInfo.environment["MEMO_WHISPER_URL"] ?? ""
    let base = env.isEmpty ? EndpointRouter.string("whisper") : env
    let code = runTool("/usr/bin/curl", ["-s", "-m", "4", "-o", "/dev/null", "-w", "%{http_code}", base + "/health"], timeout: 8)
    return code.out.trimmingCharacters(in: .whitespaces) == "200" ? base : nil
}

/// 원격 whisper(OpenAI 호환 /v1/audio/transcriptions)로 전사 — 영상은 ffmpeg 로 오디오만 추출해 업로드.
private func transcribeRemote(_ path: String, base: String) -> String {
    let ffmpeg = firstExisting([HostPlatform.cliBinPath("ffmpeg"), "/usr/local/bin/ffmpeg"]) ?? "ffmpeg"
    let audio = NSTemporaryDirectory() + "memo-stt-" + UUID().uuidString + ".mp3"
    defer { try? FileManager.default.removeItem(atPath: audio) }
    // 원본이 영상이든 오디오든 16kHz mono mp3 로 정규화 — 업로드 작고 서버 처리 일관.
    let conv = runTool(ffmpeg, ["-i", path, "-ar", "16000", "-ac", "1", "-b:a", "64k", "-y", audio], timeout: 900)
    let upload = FileManager.default.fileExists(atPath: audio) ? audio : path  // 변환 실패시 원본 시도
    let model = ProcessInfo.processInfo.environment["MEMO_WHISPER_MODEL_NAME"] ?? "Systran/faster-whisper-large-v3"
    let resp = runTool("/usr/bin/curl", [
        "-s", "-m", "1800", "\(base)/v1/audio/transcriptions",
        "-F", "file=@\(upload)", "-F", "model=\(model)", "-F", "language=ko",
    ], timeout: 1830)
    let obj: [String: Any]?
    if let data = resp.out.data(using: .utf8) {
        do {
            obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            obj = nil
        }
    } else {
        obj = nil
    }
    guard resp.code == 0,
          let obj,
          let text = obj["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        _ = conv  // ffmpeg 로그는 실패시 참고용
        fail("원격 전사 실패(\(base)) — \(resp.out.suffix(200))")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 오디오/영상 → 전사 텍스트. ffmpeg 로 16kHz mono wav 변환 후 whisper-cli 로 전사.
private func transcribeAudio(_ path: String, model: String) -> String {
    let ffmpeg = firstExisting([HostPlatform.cliBinPath("ffmpeg"), "/usr/local/bin/ffmpeg"]) ?? "ffmpeg"
    let whisper = firstExisting([HostPlatform.cliBinPath("whisper-cli"), "/usr/local/bin/whisper-cli"]) ?? "whisper-cli"
    let tmp = NSTemporaryDirectory() + "memo-stt-" + UUID().uuidString
    let wav = tmp + ".wav"
    defer {
        for path in [wav, tmp + ".txt"] {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                let ns = error as NSError
                if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError {
                    fputs("warning: removeItem \(path): \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }
    let conv = runTool(ffmpeg, ["-i", path, "-ar", "16000", "-ac", "1", "-f", "wav", "-y", wav], timeout: 300)
    guard conv.code == 0, FileManager.default.fileExists(atPath: wav) else {
        fail("오디오 변환 실패(ffmpeg) — \(conv.out.suffix(200))")
    }
    // -l auto: 언어 자동감지. -otxt/-of: txt 산출. -np/-nt: 잡음·타임스탬프 없이 본문만.
    let stt = runTool(whisper, ["-m", model, "-f", wav, "-l", "auto", "-otxt", "-nt", "-np", "-of", tmp])
    let text = (try? String(contentsOfFile: tmp + ".txt", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty else {
        if stt.code == 0 {
            // whisper 는 성공했는데 본문이 비었다 = 더미/테스트 모델(for-tests-ggml-tiny 등)이거나 무음.
            fail("전사 결과가 비었습니다 — 쓸 수 있는 whisper 모델인지 확인하세요(테스트용 tiny 모델은 빈 결과). "
                + "실모델: --model <경로> 또는 MEMO_WHISPER_MODEL. 사용 모델: \(model)")
        }
        fail("전사 실패(whisper-cli, code \(stt.code)) — \(stt.out.suffix(200))")
    }
    return text
}

/// 파일에서 텍스트·형식·작성일을 뽑는다. 형식은 확장자로 판별.
private func extractFromFile(_ path: String, whisperModel: String?) -> Extracted {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    guard let raw = try? Data(contentsOf: url) else { fail("파일을 읽을 수 없음: \(path)") }
    switch ext {
    case "pdf":
        guard let doc = PDFDocument(url: url) else { fail("PDF 를 열 수 없음: \(path)") }
        let text = doc.string ?? ""
        // PDF 메타데이터 작성일 우선, 없으면 파일 mtime.
        let created = doc.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date
        return Extracted(text: text, kind: "pdf",
                         authoredAt: isoDay(created) ?? fileModifiedDay(path), rawBytes: raw)
    case "txt", "md", "markdown", "vtt", "srt", "text", "":
        let text = String(data: raw, encoding: .utf8) ?? ""
        return Extracted(text: text, kind: "text", authoredAt: fileModifiedDay(path), rawBytes: raw)
    case "mp3", "m4a", "wav", "aac", "mp4", "mov", "m4v", "flac", "ogg", "webm":
        // 1순위: 원격 whisper 서버(gujo 50서버 faster-whisper-large-v3). 2순위: 로컬 whisper-cli+모델.
        let text: String
        if let base = remoteWhisperURL() {
            text = transcribeRemote(path, base: base)
        } else if let model = resolveWhisperModel(whisperModel) {
            text = transcribeAudio(path, model: model)
        } else {
            fail("""
            오디오/영상 전사 수단이 없습니다:
              · 원격: whisper 서버가 안 닿음(MEMO_WHISPER_URL 또는 EndpointRouterKit whisper)
              · 로컬: whisper 모델 없음(--model <경로> 또는 MEMO_WHISPER_MODEL)
            50서버가 켜져 있으면 자동으로 원격 전사합니다.
            """)
        }
        return Extracted(text: text, kind: "audio", authoredAt: fileModifiedDay(path), rawBytes: raw)
    default:
        // 알 수 없는 확장자는 UTF-8 텍스트로 시도.
        let text = String(data: raw, encoding: .utf8) ?? ""
        guard !text.isEmpty else { fail("텍스트로 읽을 수 없는 형식(.\(ext)) — 지원: pdf, txt, md, vtt, srt") }
        return Extracted(text: text, kind: "text", authoredAt: fileModifiedDay(path), rawBytes: raw)
    }
}

func runBatchNew(arguments: [String]) {
    guard arguments.count >= 2, arguments[1] == "new" else { fail(usage) }
    print(LedgerID.generate())
}

func runPublish(store: LedgerStore, author: String, arguments: [String]) {
    var title: String?
    var typeField: String?
    var origin: String?
    var tags: [String] = []
    var aliases: [String] = []
    var cites: [LedgerObject.Cite] = []
    var observes: [String] = []
    var supersedes: String?
    var retracts: String?
    var ofDecision: String?  // scene-evidence 역링크 대상 결정 객체 id (`--of`)
    var classificationDomain: String?
    var classificationKind: String?
    var classificationKnowledge: String?
    var classificationReason: String?
    var batch = ProcessInfo.processInfo.environment["MEMO_LEDGER_BATCH"]
    let allowUnclassified = arguments.contains("--allow-unclassified")
    var rest = Array(arguments.dropFirst())
    while let index = rest.firstIndex(where: { $0.hasPrefix("--") }) {
        let flag = rest[index]
        // 값 없는 불리언 플래그 — 아래 "값 두 칸 소비" 규칙 전에 걸러낸다.
        if flag == "--allow-unclassified" { rest.removeSubrange(index..<(index + 1)); continue }
        guard rest.count > index + 1 else { fail(usage) }
        let value = rest[index + 1]
        var consumed = 2
        switch flag {
        case "--title": title = value
        case "--type": typeField = value
        case "--origin": origin = value
        case "--tag": tags.append(value)
        case "--alias": aliases.append(value)
        case "--domain": classificationDomain = value
        case "--kind":
            // `--kind scene-evidence` 는 3축 분류 kind 가 아니라 객체 종류다(--type 과 동의).
            if value == PublishCompleteness.sceneEvidenceType {
                typeField = value
            } else {
                classificationKind = value
            }
        case "--knowledge": classificationKnowledge = value
        case "--classification-reason": classificationReason = value
        case "--observes": observes.append(value)   // 사건 참조 — 해석이 근거로 삼은 event id
        case "--supersedes": supersedes = value
        case "--retracts": retracts = value
        case "--of": ofDecision = value
        case "--batch": batch = value
        case "--cite":
            // --cite <id> [rel]
            if rest.count > index + 2, !rest[index + 2].hasPrefix("--") {
                cites.append(.init(id: value, rel: rest[index + 2]))
                consumed = 3
            } else {
                cites.append(.init(id: value, rel: "cites"))
            }
        default: fail("모르는 옵션: \(flag)")
        }
        rest.removeSubrange(index..<(index + consumed))
    }
    var body = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || retracts != nil else {
        fail("stdin 으로 본문을 주세요 (철회 발행만 본문 생략 가능)")
    }
    // scene-evidence — 결정 객체 역링크 독립 객체. 역링크는 evidence 쪽 cite(rel of)로만.
    if typeField == PublishCompleteness.sceneEvidenceType || ofDecision != nil {
        guard let decisionID = ofDecision else {
            fail("scene-evidence 발행에는 --of <decision-id> 가 필요합니다")
        }
        if typeField == nil { typeField = PublishCompleteness.sceneEvidenceType }
        guard typeField == PublishCompleteness.sceneEvidenceType else {
            fail("--of 는 --kind scene-evidence 발행 전용입니다 (지금 type: \(typeField ?? "없음"))")
        }
        switch PublishCompleteness.sceneEvidenceLink(of: decisionID, objects: store.scan()) {
        case .success(let cite):
            if !cites.contains(cite) { cites.append(cite) }
            body = PublishCompleteness.sceneEvidenceBody(of: decisionID, body: body)
        case .failure(let failure):
            fail(failure.message)
        }
        if let failure = PublishCompleteness.validateSceneEvidence(cites: cites) {
            fail(failure.message)
        }
    }
    let classificationFields = [classificationDomain, classificationKind, classificationKnowledge, classificationReason]
    let suppliedClassificationFields = classificationFields.compactMap { $0 }.count
    guard suppliedClassificationFields == 0 || suppliedClassificationFields == classificationFields.count else {
        fail("자동 선별은 --domain --kind --knowledge --classification-reason 을 모두 주세요")
    }
    let classification: LedgerClassificationInput?
    if suppliedClassificationFields == classificationFields.count {
        guard let domain = classificationDomain, let kind = classificationKind,
              let knowledge = classificationKnowledge, let reason = classificationReason,
              let input = LedgerClassificationInput(domain: domain, kind: kind, knowledge: knowledge, reason: reason)
        else {
            fail("분류값이 올바르지 않습니다 — domain은 8개 도메인, kind·knowledge·근거는 도움말을 확인하세요")
        }
        classification = input
    } else {
        classification = nil
    }
    // supersedes/retracts/cites 대상 실재 확인 — 없는 객체를 가리키는 발행을 막는다.
    let existing = Set(store.scan().map(\.id))
    for ref in ([supersedes, retracts].compactMap { $0 } + cites.map(\.id)) where !existing.contains(ref) {
        fail("없는 객체 참조: \(ref)")
    }
    do {
        // OKF 정합 — type 미지정이면 제목 접두어에서 유도해 명시 저장
        let derivedType = typeField ?? LedgerObject(
            id: "0", published: Date(), author: "x", title: title, body: "").effectiveType

        // 분류 기준선 집행 — **발행 시점에** 막는다.
        //
        // verify 에만 게이트를 두면 verify 를 안 치는 세션은 그대로 놓친다. 실제로
        // 오늘 아침 내가 그렇게 놓쳤고, 사용자가 요구한 것도 "놓쳤다는 걸 강제화"였다.
        // 나중에 잡는 검사는 규칙을 알려주지만, 발행을 막는 검사는 규칙을 가르친다.
        //
        // 탈출구는 남긴다(`--allow-unclassified`): 급한 메모까지 무겁게 만들면
        // 사람이 원장 밖에 적기 시작하고, 그게 더 나쁘다. 다만 **명시해야** 하므로
        // 빠뜨림과 의도적 생략이 구분된다.
        if classification == nil, !allowUnclassified, retracts == nil {
            let objects = store.scan()
            let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
            let probe = LedgerObject(
                id: "0", published: Date(), author: author, title: title,
                type: derivedType, body: body)
            if policy.requiresClassification(probe) {
                let baseline = policy.since.map { LedgerObject.iso.string(from: $0) } ?? "?"
                fail("""
                    분류 기준선(\(baseline)) 이후 지식 발행에는 3축 분류가 필요합니다.
                      같이 발행: --domain <d> --kind <k> --knowledge <n> --classification-reason <근거>
                      나중에:   --allow-unclassified  (미분류 백로그로 남습니다)
                    """)
            }
        }
        let object = try store.publish(
            author: author, title: title, type: derivedType, body: body, cites: cites,
            observes: observes, supersedes: supersedes, retracts: retracts,
            batch: batch, origin: origin, tags: tags + aliases.map { "alias:" + $0 })
        if let classification {
            let screening = try store.publishScreening(
                author: author, target: object, classification: classification, batch: batch)
            FileHandle.standardError.write(Data("선별: \(screening.id)\n".utf8))
        }
        syncIndexAfterWrite(store)
        print(object.id)
    } catch {
        fail("\(error)")
    }
}

func runCapture(store: LedgerStore, author: String, arguments: [String]) {
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
        let object = try store.publish(
            author: author, title: CLILocalization.format("CommandPublish.title", captureTitle),
            body: excerpt.isEmpty ? "(발췌 없음 — 원문은 origin 참조)" : excerpt,
            origin: urlString)
        print(CLILocalization.format("CommandPublish.print", String(object.id.prefix(8))))
        // 원본 provenance — 수집 원문을 blob 으로 봉인하고 fetch 사건을 남긴다(researcher 트리오).
        // 사건은 진행 중 작업(MEMO_LEDGER_RUN, runEngine 이 주입)에 단계로 매단다.
        let log = EventLog(root: store.root)
        var sha: String?
        if !excerpt.isEmpty {
            do {
                sha = try BlobStore(root: store.root).put(Data(excerpt.utf8))
            } catch {
                fputs("warning: capture blob put: \(error.localizedDescription)\n", stderr)
            }
        }
        do {
            try log.append(Event(
                writer: author,
                subject: object.id,
                rel: "웹 수집",
                level: .step,
                extras: Event.Extras(
                    object: urlString,
                    source: sha,
                    parent: ProcessInfo.processInfo.environment["MEMO_LEDGER_RUN"]
                )
            ))
        } catch {
            fputs("warning: capture event: \(error.localizedDescription)\n", stderr)
        }
    } catch {
        fail("\(error)")
    }
}

/// 텍스트 원문 수집 — 위키에 바로 안 넣는다. 원문을 blob 으로 불변 봉인하고, 그 원문을
/// 인용하는 근거 객체를 수집함(트리아지 대기)으로 발행한다. 이후 distiller 가 정제 → 심사대.
func runCaptureText(store: LedgerStore, author: String, arguments: [String]) {
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
        let object = try store.publish(
            author: author, title: CLILocalization.format("CommandPublish.title", title), type: "evidence",
            body: trimmed, origin: "paste:\(sha.prefix(12))", source: provenance)
        let meta = [kind, project.map { "프로젝트 \($0)" }, provenance.authoredAt.map { "작성 \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
        print(CLILocalization.format("CommandPublish.print-2", String(object.id.prefix(8)), trimmed.count, String(sha.prefix(8)), meta.isEmpty ? "" : ", \(meta)"))
        let log = EventLog(root: store.root)
        try? log.append(Event(writer: author, subject: object.id, rel: "\(kind) 수집", level: .step, extras: Event.Extras(object: sourcePath ?? "paste:\(sha.prefix(12))", source: sha, parent: ProcessInfo.processInfo.environment["MEMO_LEDGER_RUN"])))
    } catch {
        fail("\(error)")
    }
}

func runRollback(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    do {
        let published = try store.rollback(batchID: arguments[1], author: author)
        for object in published {
            print(CLILocalization.format("CommandPublish.print-3", String(object.id.prefix(8)), object.retracts != nil ? CLILocalization.string("cli.retract") : CLILocalization.string("cli.restore-prev")))
        }
    } catch {
        fail("\(error)")
    }
}

func runVerify(
    store: LedgerStore,
    worlds: [LedgerWorld] = [],
    repository: RepositoryIdentity? = nil
) {
    var violations = store.verify()
    violations.append(contentsOf: PromotionVerifier.verify(
        store: store, peerWorlds: worlds, currentRepository: repository))
    if let checkpointViolations = store.verifyCheckpoint() {
        violations.append(contentsOf: checkpointViolations)
    } else {
        FileHandle.standardError.write(Data("(체크포인트 없음 — `checkpoint` 로 기준점을 만드세요)\n".utf8))
    }
    // 작업그래프 정합성 — dangling handoff/done 은 이미 위 참조무결성이 잡는다.
    // 여기선 그 위에: done 이 task 가 아닌 걸 완료 처리 / 한 task 를 두 번 완료.
    let objects = store.scan()
    let byID = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var completeCount: [String: Int] = [:]
    for object in objects where object.effectiveType == "done" {
        for cite in object.cites where cite.rel == "completes" {
            completeCount[cite.id, default: 0] += 1
            if let target = byID[cite.id], target.effectiveType != "task" {
                violations.append(.init(id: object.id, problem: "done 이 task 아닌 객체를 완료: \(cite.id.prefix(8))"))
            }
        }
    }
    for (taskID, count) in completeCount where count > 1 {
        violations.append(.init(id: taskID, problem: "task 가 \(count)번 완료됨(중복 done)"))
    }
    let taskGraph = LedgerTaskGraph(objects: objects, currentSourceCommit: repository?.sourceCommit)
    for item in taskGraph.items {
        for warning in item.orchestration.warnings where [
            RepositoryAgentTaskWarning.Code.completionWithoutVerification,
            .verificationMismatch,
            .verificationRejected,
            .malformedBinding,
        ].contains(warning.code) {
            violations.append(.init(
                id: warning.objectId ?? item.taskId,
                problem: "repository-agent gate: \(warning.message)"))
        }
    }
    // author 감사 — 원장 루트에 authors.json(커미터→actor) 이 있으면 author 위조 검증.
    if let authorViolations = AuthorAudit.run(root: store.root, objects: objects) {
        violations.append(contentsOf: authorViolations)
    }
    // 분류 기준선 — 선언돼 있으면 그 이후 발행된 지식에 3축 분류를 요구한다.
    // 전면 게이트가 아닌 이유는 LedgerClassificationPolicy 주석에 있다: 미분류 549건
    // 위에 전면 게이트를 걸면 verify 가 첫날부터 항상 빨간불이고, 상시 빨간불은
    // 게이트를 무력화한다(오늘 프로모션 봉쇄 위반에서 실제로 그렇게 됐다).
    let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
    if policy.since != nil {
        let classified = Set(LedgerClassification(objects: objects).domain.keys)
        for object in policy.unclassified(objects: objects, classified: classified) {
            violations.append(.init(
                id: object.id,
                problem: "분류 기준선 이후 발행인데 3축 분류 없음 — "
                    + "`classify \(object.id.prefix(8)) --domain … --kind … --knowledge … --reason …`"))
        }
    }

    // 파생 인덱스 드리프트 — md 는 멀쩡한데 인덱스가 뒤처지면 `search` 가 조용히 못 찾는다.
    // 원장 무결성이 아니라 **도달성** 결함이라 지금까지 검사 항목에 없었지만, 못 찾는
    // 지식은 없는 지식과 같다. 위반으로 올려 exit≠0 을 받게 한다(고침: `index sync`).
    let indexPath = store.root.appendingPathComponent("state/index.db")
    if FileManager.default.fileExists(atPath: indexPath.path) {
        let index = LedgerIndex(root: store.root)
        let objectsDir = store.root.appendingPathComponent("objects")
        if index.isStale(objectsDir: objectsDir) {
            let indexed = index.objectCount()
            let onDisk = index.diskCensus(objectsDir: objectsDir).count
            violations.append(.init(
                id: "index",
                problem: "파생 인덱스가 뒤처짐(인덱스 \(indexed) · 디스크 \(onDisk)) "
                    + "— search 도달 불가. `index sync` 로 맞추세요"))
        }
    }
    if violations.isEmpty {
        print(CLILocalization.format("CommandPublish.print-4", store.scan().count))
    } else {
        for violation in violations { print("\(violation.id): \(violation.problem)") }
        exit(2)
    }
}

func runCheckpoint(store: LedgerStore, author: String) {
    do {
        let object = try store.publishCheckpoint(author: author)
        print(CLILocalization.format("CommandPublish.print-5", String(object.id.prefix(8)), object.title ?? ""))
    } catch {
        fail("\(error)")
    }
}


