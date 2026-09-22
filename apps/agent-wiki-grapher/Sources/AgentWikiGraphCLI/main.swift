import SingleInstanceKit
import Foundation
import InteropKit
import AppScaffoldKit
import WikiLedgerKit
import AgentWikiGraphCore
import AppPathsKit
import LocalizationKit
import CommandKit

SingleInstanceCLI.autoGuard()

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
// 파일 최상단에서 먼저 실행된다. help·version·capabilities·status 와
// 판정 실패는 통과한다(절차: swiftkit-appscaffold Documentation/gujo-managed.md).
GujoManaged.exitIfNotEntitledSync()

// agent-wiki-graph — dual-entry Helpers CLI (Foundation only).
// PATH must never point at .app/Contents/MacOS GUI (dual-entry hang 2026-07-25).

let service = AgentWikiGraphService()

// MARK: - 플래그 파서 (Foundation-only 유지; ArgumentParser 안 씀)

struct Flags {
    let all: [String]
    init(_ argv: [String]) { all = argv }

    func value(_ name: String) -> String? {
        guard let i = all.firstIndex(of: "--" + name), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
    /// `--json` (불리언).
    var json: Bool { all.contains("--json") }
    /// `--limit N`.
    var limit: Int? { value("limit").flatMap(Int.init) }
    /// `--kinds cite,supersedes`.
    var kinds: Set<WikiEdgeKind>? {
        guard let raw = value("kinds") else { return nil }
        let set = Set(raw.split(separator: ",").compactMap { WikiEdgeKind(rawValue: String($0)) })
        return set.isEmpty ? nil : set
    }
    /// positional 인자(명령 + 피연산자). `--limit N` 의 N 도 positional 이 아니게.
    func positional() -> [String] {
        var out: [String] = []
        var skipNext = false
        for a in all {
            if skipNext { skipNext = false; continue }
            if a == "--limit" || a == "--kinds" { skipNext = true; continue }
            if a.hasPrefix("--") { continue }
            out.append(a)
        }
        return out
    }
    /// 서브커맨드. 없으면 "help".
    var command: String { positional().first ?? "help" }

    static func allowedOptions(for cmd: String) -> Set<String> {
        switch cmd {
        case "centrality", "orphans": return ["--json", "--limit", "--kinds"]
        case "path", "impact": return ["--json"]
        case "status", "rebuild", "capabilities": return ["--json"]
        case "context": return ["--json", "--limit"]
        default: return ["--json", "--help", "-h", "--version", "-V"]
        }
    }
}

/// unknown 옵션을 작업 전에 exit 64 로 막는다 — 조용히 무시하면 틀린 결론을 읽는다.
func rejectUnknownOptions(_ flags: Flags) {
    let allowed = Flags.allowedOptions(for: flags.command)
    var supplied: [String] = []
    var i = 0
    while i < flags.all.count {
        let a = flags.all[i]
        if a.hasPrefix("--") {
            supplied.append(a)
            if a == "--limit" || a == "--kinds", i + 1 < flags.all.count, !flags.all[i + 1].hasPrefix("-") { i += 1 }
        } else if a.hasPrefix("-") {
            supplied.append(a)
        }
        i += 1
    }
    let unknown = Set(supplied).subtracting(allowed)
    guard unknown.isEmpty else {
        FileHandle.standardError.write(Data(
            "error: 알 수 없는 옵션: \(unknown.sorted().joined(separator: ", "))\n--help 로 사용법을 보라.\n".utf8))
        exit(64)
    }
}

@MainActor
struct CLI {
    let flags: Flags

    func run() -> Int32 {
        let pos = flags.positional()
        let cmd = pos.first ?? "help"
        let rest = Array(pos.dropFirst())
        switch cmd {
        case "help", "-h", "--help":
            usage(); return 0
        case "version", "-V", "--version":
            CLIMarketingVersion.printLine(name: "agent-wiki-graph"); return 0
        case "capabilities":
            return capabilities()
        case "open":
            return open()
        case "status":
            return emitStatus()
        case "orphans":
            return orphans(rest: rest)
        case "centrality":
            return centrality(rest: rest)
        case "impact":
            return impact(rest: rest)
        case "path":
            return pathCmd(rest: rest)
        case "rebuild":
            return rebuild()
        case "context":
            return contextCmd(rest: pos.dropFirst().map { String($0) })
        default:
            FileHandle.standardError.write(Data("unknown command: \(cmd) (try help)\n".utf8))
            usage(); return 64
        }
    }

    // MARK: - 명령

    func emitStatus() -> Int32 {
        let s = service.status()
        if flags.json {
            print(encode(s) ?? "{}")
        } else {
            print("root:        \(s.root)")
            print(CLILocalization.format("main.print", s.objectFileCount))
            print("nodes:       \(s.nodeCount)")
            print("edges:       \(s.edgeCount)")
            print("orphans:     \(s.orphanCount)")
            print("fingerprint: \(s.ledgerFingerprint)")
            if let at = s.indexedAt { print("indexedAt:   \(iso(at))") }
        }
        return 0
    }

    func orphans(rest: [String]) -> Int32 {
        let nodes = service.orphans(kinds: flags.kinds)
        let trimmed = flags.limit.map { Array(nodes.prefix($0)) } ?? nodes
        if flags.json { print(encode(trimmed) ?? "[]") }
        else {
            print(CLILocalization.format("main.print-2", nodes.count) + (flags.limit != nil ? CLILocalization.format("main.top-shown", String(trimmed.count)) : ""))
            for n in trimmed { print("  \(n.id.prefix(12))…  [\(n.type)]  \(n.title)") }
        }
        return 0
    }

    func centrality(rest: [String]) -> Int32 {
        let limit = flags.limit ?? 20
        let ranked = service.centrality(limit: limit, kinds: flags.kinds)
        if flags.json {
            let arr = ranked.map { CentralityRow(id: $0.0.id, title: $0.0.title, type: $0.0.type, inDegree: $0.1) }
            print(encode(arr) ?? "[]")
        } else {
            print(CLILocalization.format("main.print-3", ranked.count))
            for (n, d) in ranked { print("  \(String(repeating: " ", count: max(0,4-String(d).count)))\(d)  \(n.id.prefix(12))…  [\(n.type)]  \(n.title)") }
        }
        return 0
    }

    func impact(rest: [String]) -> Int32 {
        guard let prefix = rest.first, !prefix.isEmpty else {
            FileHandle.standardError.write(Data("사용법: impact <id접두어>\n".utf8)); return 64
        }
        guard let nodes = service.impact(of: prefix) else {
            FileHandle.standardError.write(Data("id 미해상(모호하거나 없음): \(prefix) — 전체 id 또는 고유 접두어\n".utf8)); return 1
        }
        if flags.json { print(encode(nodes) ?? "[]") }
        else {
            print(CLILocalization.format("main.print-4", prefix, nodes.count))
            for n in nodes { print("  \(n.id.prefix(12))…  [\(n.type)]  \(n.title)") }
        }
        return 0
    }

    func pathCmd(rest: [String]) -> Int32 {
        guard rest.count >= 2 else {
            FileHandle.standardError.write(Data("사용법: path <id접두어> <id접두어>\n".utf8)); return 64
        }
        guard let result = service.path(from: rest[0], to: rest[1]) else {
            FileHandle.standardError.write(Data("경로 없음(또는 id 미해상): \(rest[0]) → \(rest[1])\n".utf8)); return 1
        }
        if flags.json { print(encode(result.nodes) ?? "[]") }
        else {
            print(CLILocalization.format("main.print-5", String(result.path.count)))
            for n in result.nodes { print("  \(n.id.prefix(12))…  [\(n.type)]  \(n.title)") }
        }
        return 0
    }

    func rebuild() -> Int32 {
        let g = service.rebuild()
        StateMirrorAdoption.publish(summary: service.status())
        print("rebuild: nodes=\(g.nodeCount) edges=\(g.edgeCount) orphans=\(g.orphans().count)")
        return 0
    }

    func contextCmd(rest: [String]) -> Int32 {
        let query = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            FileHandle.standardError.write(Data("사용법: context <질의...>\n".utf8)); return 64
        }
        let hits = service.context(query, limit: flags.limit ?? 20)
        if hits.isEmpty {
            print(CLILocalization.format("main.print-6", query))
            return 1
        }
        if flags.json {
            let arr = hits.map { hit in
                [
                    "id": hit.node.id,
                    "title": hit.node.title,
                    "type": hit.node.type,
                    "score": hit.score,
                    "seed": hit.seed,
                ] as [String: Any]
            }
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: arr,
                    options: [.prettyPrinted, .sortedKeys]
                )
                print(String(data: data, encoding: .utf8) ?? "[]")
            } catch {
                fputs("context json: \(error.localizedDescription)\n", stderr)
                print("[]")
            }
        } else {
            print(CLILocalization.format("main.print-7", hits.count))
            for h in hits {
                let mark = h.seed ? "★" : "·"
                print("  \(mark) \(String(repeating: " ", count: max(0,3-String(h.score).count)))\(h.score)  \(h.node.id.prefix(12))…  [\(h.node.type)]  \(h.node.title)")
            }
        }
        return 0
    }

    // MARK: - capabilities / open / usage

    func capabilities() -> Int32 {
        let caps = InteropKit.Capabilities(
            name: "agent-wiki-graph",
            cli: HostPlatform.cliBinPath("agent-wiki-graph"),
            commands: [
                .init(name: "capabilities", summary: "이 계약 출력", json: true),
                .init(name: "help", summary: "도움말", json: false),
                .init(name: "status", summary: "그래프 인덱스 요약(노드/엣지/고립 수)", json: true),
                .init(name: "orphans", summary: "고립 객체(in-degree=0) — 죽은/안 불리는 지식 [--limit N]", json: true),
                .init(name: "centrality", summary: "중심성(in-degree) 랭킹 [--limit N]", json: true),
                .init(name: "impact", summary: "<id접두어> 가 (전이적으로) 의존하는 노드 역순회", json: true),
                .init(name: "path", summary: "<a> <b> 인용 경로(BFS)", json: true),
                .init(name: "context", summary: "질의로 GraphRAG 검색 [--limit N]", json: true),
                .init(name: "rebuild", summary: "원장 전체 재인덱스", json: false),
                .init(name: "version", summary: "버전", json: false),
                .init(name: "open", summary: "GUI 앱 열기", json: false),
            ],
            state: [
                .init(
        path: DurableAppLayout.tildePath(DurableAppLayout.sqliteURL(slug: "agent-wiki-graph")),
        what: "설정·작업 sqlite (정본)"
    ),
                .init(path: "~/.swift-app-state/agent-wiki-graph.json", what: "그래프 인덱스 요약(노드/엣지/고립 수·원장 지문)"),
                .init(path: "~/.swift-app-state/agent-wiki-graph/index.json", what: "파생 그래프 캐시(원장 mtime 으로 신선도 판정)"),
            ],
            health: .init(
                command: "\(HostPlatform.cliBinPath("agent-wiki-graph")) capabilities",
                freshness: "~/.swift-app-state/agent-wiki-graph.json"
            ),
            depends: []
        )
        do {
            let data = try Envelope.ok(caps)
            print(String(data: data, encoding: .utf8) ?? "{}")
        } catch {
            fputs("capabilities: \(error.localizedDescription)\n", stderr)
            print("{}")
        }
        return 0
    }

    func open() -> Int32 {
        let hint = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let safeResult = SafeProcessRunner.run(
            "/usr/bin/open",
            ["-a", hint]
        )
            FileHandle.standardError.write(Data("error: open failed: \(error)\n".utf8)); return 1
        }
        return 0
    }

    func usage() {
        print(
            """
            agent-wiki-graph — Agent Wiki 원장의 파생 지식그래프 분석기 (read-only)

            명령:
              status                     그래프 인덱스 요약
              orphans [--limit N]        고립 객체(in-degree=0)
              centrality [--limit N]     중심성(in-degree) 랭킹
              impact <id접두어>          <id> 에 의존하는 노드 역순회
              path <a> <b>               인용 경로(BFS)
              rebuild                    원장 전체 재인덱스
              capabilities               이 계약({ok,result} 봉투)
              version / help / open

            공통: --json (기계 출력), --kinds cite,supersedes (엣지 종류 필터)
            원장: ~/gujo-wiki (GUJO_WIKI_ROOT 로 override)
            """
        )
    }
}

// MARK: - 도우미

private struct CentralityRow: Codable {
    let id: String
    let title: String
    let type: String
    let inDegree: Int
}

func encode<T: Encodable>(_ value: T) -> String? {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? e.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
}

private enum CLIFormatters {
    static let isoDateFormatter = ISO8601DateFormatter()
}

func iso(_ d: Date) -> String {
    CLIFormatters.isoDateFormatter.string(from: d)
}

// MARK: - 진입

let flags = Flags(Array(CommandLine.arguments.dropFirst()))
// help/version 은 unknown 검사 전에 exit 0.
if flags.command == "help" || flags.command == "-h" || flags.command == "--help" {
    CLI(flags: flags).usage(); exit(0)
}
rejectUnknownOptions(flags)

exit(await CLI(flags: flags).run())
