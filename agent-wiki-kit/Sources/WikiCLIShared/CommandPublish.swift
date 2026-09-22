import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import PDFKit
import StateRootKit

/// 파일 → 텍스트 추출 결과. 원본 바이트는 그대로 봉인하고, 여기서 뽑은 텍스트를 수집물 본문으로 쓴다.
struct Extracted {
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
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path), // try?: guard-return (file may not exist)
          let mtime = attrs[.modificationDate] as? Date else { return nil }
    return isoDay(mtime)
}

/// 외부 명령 동기 실행 — (exit code, stdout+stderr). 워치독 포함(매달리면 SIGTERM→SIGKILL).
private func runTool(_ launch: String, _ args: [String], timeout: TimeInterval = 1800) -> (code: Int32, out: String) {
    let result = CommandKitSync.run(launch, args, timeout: timeout)
    let exitCodeNotFound: Int32 = 127
    if result.exitCode == exitCodeNotFound, result.stdout.isEmpty {
        return (-1, result.stderr)
    }
    let out = result.stdout + result.stderr
    if result.exitCode == 15 || result.exitCode == 9 {
        return (-2, out + "\n(시간초과 \(Int(timeout))s — 종료됨)")
    }
    return (result.exitCode, out)
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
private var defaultWhisperHost: String {
    ProcessInfo.processInfo.environment["MEMO_WHISPER_URL"]
        ?? ["http://", "whisper.50", ".internal.kr"].joined() // allow:gujo-endpoint
}

private func remoteWhisperURL() -> String? {
    let base = defaultWhisperHost
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
    guard resp.code == 0,
          let data = resp.out.data(using: .utf8) else {
        _ = conv
        fail("원격 전사 실패(\(base)) — 응답 없음: \(resp.out.suffix(200))")
    }
    let obj: [String: Any]
    do {
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("원격 전사 실패(\(base)) — JSON 최상위가 딕셔너리가 아님")
        }
        obj = parsed
    } catch {
        _ = conv
        fail("원격 전사 실패(\(base)) — JSON 디코드 실패: \(error)")
    }
    guard let text = obj["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fail("원격 전사 실패(\(base)) — text 필드 없음: \(resp.out.suffix(200))")
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
func extractFromFile(_ path: String, whisperModel: String?) -> Extracted {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    let raw: Data
    do { raw = try Data(contentsOf: url) } catch { fail("파일을 읽을 수 없음: \(path): \(error.localizedDescription)") }
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
              · 원격: whisper 서버가 안 닿음(MEMO_WHISPER_URL, 기본 \(defaultWhisperHost))
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

public func runBatchNew(arguments: [String]) {
    guard arguments.count >= 2, arguments[1] == "new" else { fail(usage) }
    print(LedgerID.generate()) // allow:debug
}

struct PublishArgs {
    var title: String?
    var typeField: String?
    var origin: String?
    var tags: [String] = []
    var aliases: [String] = []
    var cites: [LedgerObject.Cite] = []
    var observes: [String] = []
    var supersedes: String?
    var retracts: String?
    /// scene-evidence 역링크 대상 결정 객체 id (`--of`).
    var ofDecision: String?
    var classificationDomain: String?
    var classificationKind: String?
    var classificationKnowledge: String?
    var classificationReason: String?
    var batch: String?
    var allowUnclassified: Bool = false
}

private func consumeFlag(
    flag: String,
    value: String,
    rest: [String],
    index: Int,
    args: inout PublishArgs
) -> Int {
    switch flag {
    case "--title": args.title = value
    case "--type": args.typeField = value
    case "--origin": args.origin = value
    case "--tag": args.tags.append(value)
    case "--alias": args.aliases.append(value)
    case "--domain": args.classificationDomain = value
    case "--kind":
        if value == PublishCompleteness.sceneEvidenceType {
            args.typeField = value
        } else {
            args.classificationKind = value
        }
    case "--knowledge": args.classificationKnowledge = value
    case "--classification-reason": args.classificationReason = value
    case "--observes": args.observes.append(value)
    case "--supersedes": args.supersedes = value
    case "--retracts": args.retracts = value
    case "--of": args.ofDecision = value
    case "--batch": args.batch = value
    case "--cite":
        if rest.count > index + 2, !rest[index + 2].hasPrefix("--") {
            args.cites.append(.init(id: value, rel: rest[index + 2]))
            return 3
        } else {
            args.cites.append(.init(id: value, rel: "cites"))
        }
    default: fail("모르는 옵션: \(flag)")
    }
    return 2
}

private func parsePublishArgs(_ arguments: [String]) -> PublishArgs {
    var args = PublishArgs()
    args.batch = ProcessInfo.processInfo.environment["MEMO_LEDGER_BATCH"]
    args.allowUnclassified = arguments.contains("--allow-unclassified")
    var rest = Array(arguments.dropFirst())
    while let index = rest.firstIndex(where: { $0.hasPrefix("--") }) {
        let flag = rest[index]
        if flag == "--allow-unclassified" { rest.removeSubrange(index..<(index + 1)); continue }
        guard rest.count > index + 1 else { fail(usage) }
        let consumed = consumeFlag(flag: flag, value: rest[index + 1], rest: rest, index: index, args: &args)
        rest.removeSubrange(index..<(index + consumed))
    }
    return args
}

private func resolveClassification(_ args: PublishArgs) -> LedgerClassificationInput? {
    let fields = [args.classificationDomain, args.classificationKind,
                  args.classificationKnowledge, args.classificationReason]
    let supplied = fields.compactMap { $0 }.count
    guard supplied > 0 else { return nil }
    guard supplied == fields.count else {
        fail("자동 선별은 --domain --kind --knowledge --classification-reason 을 모두 주세요")
    }
    guard let domain = args.classificationDomain, let kind = args.classificationKind,
          let knowledge = args.classificationKnowledge, let reason = args.classificationReason,
          let input = LedgerClassificationInput(domain: domain, kind: kind, knowledge: knowledge, reason: reason)
    else {
        fail("분류값이 올바르지 않습니다 — domain은 8개 도메인, kind·knowledge·근거는 도움말을 확인하세요")
    }
    return input
}

private func validateReferences(
    store: LedgerStore, supersedes: String?, retracts: String?, cites: [LedgerObject.Cite]
) {
    let existing = Set(store.scan().map(\.id))
    for ref in ([supersedes, retracts].compactMap { $0 } + cites.map(\.id)) where !existing.contains(ref) {
        fail("없는 객체 참조: \(ref)")
    }
}

private func enforceClassificationBaseline(
    store: LedgerStore, author: String, title: String?,
    derivedType: String?, body: String
) {
    let objects = store.scan()
    let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
    let probe = LedgerObject(
        id: "0", published: Date(), author: author, title: title,
        type: derivedType, body: body)
    guard policy.requiresClassification(probe) else { return }
    let baseline = policy.since.map { LedgerObject.iso.string(from: $0) } ?? "?"
    fail("""
        분류 기준선(\(baseline)) 이후 지식 발행에는 3축 분류가 필요합니다.
          같이 발행: --domain <d> --kind <k> --knowledge <n> --classification-reason <근거>
          나중에:   --allow-unclassified  (미분류 백로그로 남습니다)
        """)
}

private func applySceneEvidenceLink(args: inout PublishArgs, body: inout String, store: LedgerStore) {
    guard args.typeField == PublishCompleteness.sceneEvidenceType || args.ofDecision != nil else { return }
    guard let decisionID = args.ofDecision else {
        fail("scene-evidence 발행에는 --of <decision-id> 가 필요합니다")
    }
    if args.typeField == nil { args.typeField = PublishCompleteness.sceneEvidenceType }
    guard args.typeField == PublishCompleteness.sceneEvidenceType else {
        fail("--of 는 --kind scene-evidence 발행 전용입니다 (지금 type: \(args.typeField ?? "없음"))")
    }
    switch PublishCompleteness.sceneEvidenceLink(of: decisionID, objects: store.scan()) {
    case .success(let cite):
        if !args.cites.contains(cite) { args.cites.append(cite) }
        body = PublishCompleteness.sceneEvidenceBody(of: decisionID, body: body)
    case .failure(let failure):
        fail(failure.message)
    }
    if let failure = PublishCompleteness.validateSceneEvidence(cites: args.cites) {
        fail(failure.message)
    }
}

public func runPublish(store: LedgerStore, author: String, arguments: [String]) {
    var args = parsePublishArgs(arguments)
    var body = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || args.retracts != nil else {
        fail("stdin 으로 본문을 주세요 (철회 발행만 본문 생략 가능)")
    }
    applySceneEvidenceLink(args: &args, body: &body, store: store)
    let classification = resolveClassification(args)
    validateReferences(store: store, supersedes: args.supersedes, retracts: args.retracts, cites: args.cites)
    do {
        let derivedType = args.typeField ?? LedgerObject(
            id: "0", published: Date(), author: "x", title: args.title, body: "").effectiveType
        if classification == nil, !args.allowUnclassified, args.retracts == nil {
            enforceClassificationBaseline(
                store: store, author: author, title: args.title,
                derivedType: derivedType, body: body)
        }
        let publishExtras = LedgerPublishExtras(
            cites: args.cites, observes: args.observes,
            supersedes: args.supersedes, retracts: args.retracts,
            batch: args.batch, origin: args.origin,
            tags: args.tags + args.aliases.map { "alias:" + $0 })
        let object = try store.publish(
            author: author, title: args.title,
            type: derivedType, body: body, extras: publishExtras)
        if let classification {
            let screening = try store.publishScreening(
                author: author, target: object, classification: classification, batch: args.batch)
            FileHandle.standardError.write(Data("선별: \(screening.id)\n".utf8))
        }
        syncIndexAfterWrite(store)
        print(object.id) // allow:debug
    } catch {
        fail("\(error)")
    }
}

public func runRollback(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    do {
        let published = try store.rollback(batchID: arguments[1], author: author)
        for object in published {
            print("발행: \(object.id.prefix(8))  \(object.retracts != nil ? "철회" : "이전 판 복원")") // allow:debug
        }
    } catch {
        fail("\(error)")
    }
}

public func runCheckpoint(store: LedgerStore, author: String) {
    do {
        let object = try store.publishCheckpoint(author: author)
        print("체크포인트 발행: \(object.id.prefix(8))  (\(object.title ?? ""))") // allow:debug
    } catch {
        fail("\(error)")
    }
}
