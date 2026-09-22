import Foundation
import KnowledgeBaseWikiCore

/// PATH 바이너리 이름에 맞춘 사용법 헤더.
/// 호출된 이름(agent-wiki / knowledge-base-wiki / memo-citation-ledger)을 그대로 쓴다. 정본은 agent-wiki.
public func cliToolName() -> String {
    let base = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    if base == "memo-citation-ledger" || base.hasPrefix("memo-citation-ledger") {
        return "memo-citation-ledger"
    }
    if base == "knowledge-base-wiki" || base.hasPrefix("knowledge-base-wiki") {
        return "knowledge-base-wiki"
    }
    if base == "agent-wiki" || base.hasPrefix("agent-wiki") {
        return "agent-wiki"
    }
    return DualEntry.cliProductName
}
public var usage: String {
    let tool = cliToolName()
    return """
usage: \(tool) [--as <author>] [--world <name>] <command> [args]
       leading --as/--world only

  help | --help | -h              이 도움말 출력(원장 설정 불필요)
  hook authoring                  하네스 훅 stdin → ~/.agent-wiki/authoring.json (원장 설정 불필요)
  init <경로>                      원장 루트 지정·생성
  capture <url> [--title <제목>]   웹 원자료 수집 → 수집함(트리아지 대기)으로 발행. 본문은 stdin(발췌)
  publish [--title <제목>] [--type <유형>] [--origin <url>] [--tag <tag>|--alias <별칭>]...
          [--cite <id> [rel]]... [--observes <event-id>]... [--supersedes <id>]
          [--retracts <id>] [--batch <id>] [--domain <d> --kind <k> --knowledge <n>
          --classification-reason <근거>] [--allow-unclassified]
                                  stdin 본문으로 새 객체 발행. 3축+근거를 주면 선별 객체도 같은 batch에 자동 발행
  classify <id|제목> --domain <d> --kind <k> --knowledge <n> --reason <근거>
                                  기존 객체에 선별 객체를 발행. 기존 선별은 개정해 최신 분류만 투영
  show <id접두어|제목>             객체 출력(본문 포함) — id 접두어 또는 제목 부분일치
  list [--all] [--json]           head 목록(--all 이면 전체, 시간순)
  history <id접두어>               개정 계보(supersedes 사슬)
  cited-by <id접두어>              이 객체를 인용한 객체들
  rollback <batch-id>             작업 묶음 일괄 롤백(재발행/철회 — 역사에 남음)
  search <질의어> [--fleet] [--as-agent <id>] [--domain <d>] [--kind <k>] [--knowledge <tech|domain|preference>] [--limit N] [--json]
  context <질문> [--fleet] [--as-agent <id>]
  path <id접두어> <id접두어>        두 객체 사이 인용 경로 추적(BFS) — "이 결론이 어디서 왔나"
  verify                          전 객체 무결성 검사(변조·참조·중복·삭제)
  \(tool) repository summary [--path <repo>] --json
                                  canonical repository·task·knowledge·promotion·integrity v1 계약
  task bind <task> --runtime-task <id> --dispatch <id> [--knowledge <id>] [--rule <text>] --json
  task verify <task> --checker <id> --outcome verified|rejected --json
  orchestration adapter [--file <event.json>] --json
                                  versioned Orca task/dispatch/worker_done/checker JSON(stdin) adapter
  orchestration capsule|context <task> --json
                                  canonicalTaskId·runtime·dispatch·bounded knowledge/rules·stale/gate context
  task done <task> --verification <receipt-id> | list [--open] [--json] | new|handoff|chain …
                                  adapter/capsule/context는 orchestration의 호환 alias; verified receipt 없이는 done 쓰기 거부
  task knowledge-candidate <task> "<제목>"
                                  검증 완료 작업의 재사용 노하우를 repo에 먼저 발행(stdin 본문, 승격 후보 태그)
  \(tool) promotion preview <object-id> --to gujo --json
  \(tool) promotion publish <object-id> --to gujo --confirm --json
                                  repo 지식을 공유 gujo world로 명시적 프로모션 + 양방향 불변 영수증
  checkpoint                      현재 객체 집합 증언 발행(삭제 감지 기준점)
  batch new                       새 batch id 발급(export MEMO_LEDGER_BATCH=...)
  world list [--json]                 로컬 1인칭 / 원격 공유 / 저장소 원장
  world use <이름>|add <이름> <경로>   세계관 전환·등록
  world init-repo [<경로>|--here]           repo/앱에 .wiki 온보딩
  fleet list|doctor|scan|register|remove   중앙 관제 레지스트리
  pull --agent <id> --query|ids|event|blob … [--max N]
                                  max는 1...100으로 강제 clamp
  weight show|set --world|--domain … --w N
  okf-export <출력디렉터리>         위키 층(개념·엔티티·색인)을 OKF v0.1 번들로 내보내기
  agent run <역할> [--canonical-task <id> --runtime-task <id> --dispatch <id>] <작업>
                                  .agents/roles 역할 실행; canonical dispatch면 worker_done 기록
  agent role list [--json] | create <kebab-id> [--name … --summary … --engine …]
                                  저장소 책임 역할 조회·생성(create 담당범위는 stdin)
  agent sync                      역할 정의 파일 변경을 원장에 개정판으로 포착
  agent evolve <역할>              반려된 심사 피드백을 모아 저장소 역할(.agents/roles/<역할>.md)을 다음 세대로 개정
  tick checkpoint|librarian|verifier|reaper   운영 루프 1회 실행 (launchd 가 부름)
  backup                          restic 불변 백업 (야간 launchd 가 부름)
  policy show|classification-baseline --since now --reason <근거>
                                  분류 기준선 — 이 시각 이후 발행 지식에 3축 분류를 요구
  structure [--json]              저장 3층(봉인·해석·파생)과 층 사이 배선 완성도 실측
  index rebuild|sync|status|blob-event …
  schedule [list]                 틱 launchd 스케줄 관리(누락 등록) — CLI 가 소유
  dual-entry [--json]             PATH dual-entry 자가진단 (GUI 심링크/가장 탐지, 원장 불필요)
  skill-install|skill-uninstall|skill-status [--json]
                                  coding-agent skills 부착/해제/상태 (원장 불필요, install 시 자동 부착)
  recent [N]                      지식층 최근 변경 피드(신규·개정·철회) — 나무위키 RecentChanges
  discuss                         위키 토론(이의·질문·수정요청) — 미답변 우선
  diff <id> [<id2>]               개정 비교(라인 diff) — 나무위키 비교/역사
  learn                           학습 지표(일자별 성공률·개정·철회·경험칙) — 경험학습 측정
  rules [역할]                    주입될 경험칙 미리보기(SPL — 회고를 실행 프롬프트로)
  blob put [<파일>]|get <sha>|open <sha>|info <sha>|refs <sha>|path|verify|list|gc   원본 blob (불변, 사건이 sha 로 참조)
                                  open=기본앱으로(PDF·MP3) · info=종류·크기·연결 · refs=역참조
  event start --subject <> --rel <> [--source <sha>]   작업(run) 시작 → run-id 출력 (outcome=pending)
  event step --parent <run-id> --subject <> --rel <> [--source <sha>]   작업 안 단계 기록
  event ok|fail <run-id> [--attr k=v]...   작업 완료(성공/실패) — 좌초 판정 기준
  event append|tree|tail [N]|count   사건 로그 (뎁스 run>step>detail, 사실 기록. 판단은 md 로)
  graph rebuild|status|timeline <id>|neighbors <id>|interpretations <event-id>   파생 그래프 (객체+사건 순회)
  app area <영역>|destination <목적지>|jump <id>|select <id>
                                  실행 중인 앱 조종 (상태 미러로 확인)
  root                            원장 루트 출력

exit: 0 성공 · 1 실패 · 2 verify 위반 발견
"""
}


public func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

public func printJSON(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    do {
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            fail("JSON 인코딩 실패: UTF-8 변환 불가")
        }
        print(text) // allow:debug
    } catch {
        fail("JSON 인코딩 실패: \(error.localizedDescription)")
    }
}

/// 인덱스가 있으면 열고 신선도 보장 후 반환(읽기 가속). 없으면 nil → 호출측이 스캔 폴백.
public func freshIndex(_ store: LedgerStore) -> LedgerIndex? {
    let p = store.root.appendingPathComponent("state/index.db")
    guard FileManager.default.fileExists(atPath: p.path) else { return nil }
    let index = LedgerIndex(root: store.root)
    index.ensureFresh(objectsDir: store.root.appendingPathComponent("objects"))
    return index
}

/// 발행 직후 파생 인덱스를 따라오게 한다. 인덱스는 캐시(md 가 정본)라 실패해도 조용히
/// 넘어가지만, 이걸 안 하면 방금 발행한 객체가 다음 `search` 에 안 잡힌다 — 읽기 쪽에서
/// 신선도를 보장해도 쓰기 직후 한 번 밀어주는 편이 싸고 확실하다.
public func syncIndexAfterWrite(_ store: LedgerStore) {
    let p = store.root.appendingPathComponent("state/index.db")
    guard FileManager.default.fileExists(atPath: p.path) else { return }
    LedgerIndex(root: store.root).sync(objectsDir: store.root.appendingPathComponent("objects"))
    // 관계도도 파생 캐시다 — 인덱스만 따라오게 하고 그래프를 놔두면 "노드가 객체보다
    // 적다"는 미달이 시간이 갈수록 벌어진다(실측 1538/1645). 같은 자리에서 갱신한다.
    let graphPath = store.root.appendingPathComponent("state/graph.db")
    guard FileManager.default.fileExists(atPath: graphPath.path) else { return }
    let objects = store.scan()
    LedgerGraph(root: store.root).rebuild(objects: objects, events: EventLog(root: store.root).all())
}

/// 정확한 id 로 객체 1개 로드 — 인덱스로 파일 1개만(스캔 없이), 없으면 스캔 폴백.
public func loadObject(_ store: LedgerStore, id: String) -> LedgerObject? {
    if let index = freshIndex(store), let path = index.pathFor(id: id) {
        do {
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            if let obj = LedgerObject.parse(text)?.object { return obj }
        } catch {
            fputs("index loadObject failed: \(error)\n", stderr)
        }
    }
    return store.scan().first(where: { $0.id == id })
}

/// id 접두어 **또는 제목**으로 객체를 찾는다. 인덱스가 있으면 md 전체 스캔(무상태 CLI 라 매번 수 초)
/// 대신 인덱스로 id 를 해석하고 **파일 1개만** 읽는다. 인덱스 없으면 옛 스캔 폴백.
public func resolve(_ store: LedgerStore, _ prefix: String) -> LedgerObject {
    let indexPath = store.root.appendingPathComponent("state/index.db")
    if FileManager.default.fileExists(atPath: indexPath.path) {
        let index = LedgerIndex(root: store.root)
        index.ensureFresh(objectsDir: store.root.appendingPathComponent("objects"))
        let ids = index.resolveIDs(prefix)
        if ids.count == 1, let path = index.pathFor(id: ids[0]) {
            do {
                let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
                if let obj = LedgerObject.parse(text)?.object { return obj }
            } catch {
                fputs("index resolve failed: \(error)\n", stderr)
            }
        }
        if ids.count > 1 {
            let sample = ids.prefix(10).map { "  " + String($0.prefix(12)) }.joined(separator: "\n")
            fail("여러 개 매칭(\(ids.count)건) — 더 좁혀 주세요:\n\(sample)")
        }
        // ids 비었으면(인덱스 지연 등) 스캔 폴백으로.
    }
    let objects = store.scan()
    let candidates = store.resolveCandidates(objects, query: prefix)
    if candidates.count == 1 {
        return candidates[0]
    } else if candidates.count > 1 {
        let sample = candidates.prefix(10).map { "  " + String($0.id.prefix(12)) }.joined(separator: "\n")
        fail("여러 개 매칭(\(candidates.count)건) — 더 좁혀 주세요:\n\(sample)")
    } else {
        fail("객체를 못 찾음(또는 접두어 중복): \(prefix)")
    }
}
