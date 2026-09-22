import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import LocalizationKit
import WikiCLIShared

// gujo 원장 전송로 — git 정본(seed=GitLab) + 피어 pull-only mesh.
// `status` 가 먼저인 이유: 이전 전송로(syncthing)는 뒤처짐이 안 보여서 조용히 죽었다.

private func gujoRoot(arguments: [String]) -> URL {
    if let index = arguments.firstIndex(of: "--root"), index + 1 < arguments.count {
        return URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
    }
    let config = LedgerConfig.load()
    if let world = config.effectiveWorlds.first(where: { $0.name == "gujo-wiki" }) {
        return URL(fileURLWithPath: world.rootPath)
    }
    return StateRootKit.url("gujo-wiki")
}

private func emit(_ value: some Encodable, json: Bool, plain: () -> Void) {
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {
            _ = error
        }
    } else {
        plain()
    }
}

func runGujo(arguments: [String]) {
    let json = arguments.contains("--json")
    let sync = GujoSync(root: gujoRoot(arguments: arguments))
    let sub = arguments.count >= 2 ? arguments[1] : "status"

    switch sub {
    case "status":
        let state = sync.status(probeRemote: arguments.contains("--probe"))
        emit(state, json: json) {
            guard state.isRepository else {
                print(CLILocalization.format("CommandGujo.print", sync.root.path))
                // 안내가 죽은 경로를 알려주면 안 된다 — VPN 이 끊기면 SSH 는 죽고
                // 공개 HTTPS 는 산다. 지금 도달하는 주소를 카탈로그에 물어 출력한다.
                print("  → clone: git clone \(GujoWikiRemote.current()) ~/gujo-wiki")
                return
            }
            let mark = state.needsAttention ? "⚠︎" : "●"
            print("\(mark) gujo-wiki  \(sync.root.path)")
            print(CLILocalization.format("CommandGujo.print-2", state.head ?? "?", state.ahead, state.behind, state.dirty))
            if arguments.contains("--probe") {
                print(CLILocalization.format("CommandGujo.print-3", state.remoteReachable ? "OK" : CLILocalization.string("cli.failed")))
            }
            if let last = state.lastSync {
                let ago = Int(Date().timeIntervalSince(last) / 3600)
                print(CLILocalization.format("CommandGujo.print-4", ago))
            } else {
                print(CLILocalization.string("CommandGujo.print-5"))
            }
            print(CLILocalization.format("CommandGujo.print-6", state.blobsLocal))
            if state.peers.isEmpty {
                print(CLILocalization.string("CommandGujo.print-7"))
            } else {
                for peer in state.peers {
                    let delta = [peer.aheadOfUs.map { "피어가 +\($0)" },
                                 peer.behindUs.map { "우리가 +\($0)" }]
                        .compactMap { $0 }.joined(separator: " · ")
                    print(CLILocalization.format("CommandGujo.print-8", peer.name, peer.url, delta))
                }
            }
        }

    case "sync":
        let peer = arguments.firstIndex(of: "--peer").flatMap { index -> String? in
            index + 1 < arguments.count ? arguments[index + 1] : nil
        }
        switch sync.sync(peer: peer) {
        case .success(let outcome):
            emit(outcome, json: json) {
                print("fetch: \(outcome.fetched.joined(separator: ", "))")
                print(CLILocalization.format("CommandGujo.print-9", outcome.merged ? CLILocalization.string("cli.done") : CLILocalization.string("cli.none"), outcome.pushed ? CLILocalization.string("cli.done") : (peer == nil ? CLILocalization.string("cli.failed") : CLILocalization.string("cli.skip-pullonly"))))
                print("HEAD \(outcome.head ?? "?")")
                for message in outcome.messages where !message.isEmpty { print("  \(message)") }
            }
        case .failure(let error):
            fail("gujo sync 실패 — \(error.message)")
        }

    case "peer":
        let action = arguments.count >= 3 ? arguments[2] : "list"
        switch action {
        case "list":
            let peers = sync.peers()
            emit(peers, json: json) {
                if peers.isEmpty { print(CLILocalization.string("CommandGujo.print-10")) }
                for peer in peers { print("\(peer.name)\t\(peer.url)") }
            }
        case "add":
            guard arguments.count >= 5 else { fail("사용: gujo peer add <이름> <url>") }
            switch sync.addPeer(name: arguments[3], url: arguments[4]) {
            case .success: print(CLILocalization.format("CommandGujo.print-11", arguments[3]))
            case .failure(let error): fail(error.message)
            }
        case "remove":
            guard arguments.count >= 4 else { fail("사용: gujo peer remove <이름>") }
            switch sync.removePeer(name: arguments[3]) {
            case .success: print(CLILocalization.format("CommandGujo.print-12", arguments[3]))
            case .failure(let error): fail(error.message)
            }
        default:
            fail("gujo peer <list|add|remove>")
        }

    case "blob":
        runGujoBlob(sync: sync, arguments: arguments, json: json)

    default:
        print("""
        사용: agent-wiki gujo <명령>

          status [--probe] [--json]     ahead/behind·미커밋·피어·blobs (--probe 는 시드 도달성까지)
          sync [--peer <이름>] [--json] 시드와 왕복. --peer 는 fetch·merge 만(pull-only)
          peer list|add|remove          피어 관리 — 추가 시 push 는 자동 비활성
          blob status|pull|push [sha…]  blob 스토리지(S3) 왕복 — 기본 시드 R2 `gujo-wiki-blobs`
          blob config [--access-key … --secret-key …]  자격 저장(.git/gujo-s3.json, 0600)

        전역: --root <경로>  (기본: world `gujo-wiki`, 없으면 ~/gujo-wiki)
        blob 자격은 env(GUJO_S3_ACCESS_KEY/SECRET_KEY[/ENDPOINT/BUCKET]) 가 파일보다 우선.
        """)
    }
}

// MARK: - blob (S3 왕복 — 기본 R2, gujo-s3.json/env 로 구성)

private func runGujoBlob(sync: GujoSync, arguments: [String], json: Bool) {
    let action = arguments.count >= 3 ? arguments[2] : "status"
    let root = sync.root

    if action == "config" {
        var config = GujoBlobConfig.load(root: root)
            ?? GujoBlobConfig(accessKey: "", secretKey: "")
        func opt(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count
            else { return nil }
            return arguments[index + 1]
        }
        var changed = false
        if let v = opt("--endpoint") { config.endpoint = v; changed = true }
        if let v = opt("--bucket") { config.bucket = v; changed = true }
        if let v = opt("--region") { config.region = v; changed = true }
        if let v = opt("--access-key") { config.accessKey = v; changed = true }
        if let v = opt("--secret-key") { config.secretKey = v; changed = true }
        if changed {
            guard !config.accessKey.isEmpty, !config.secretKey.isEmpty else {
                fail("access-key·secret-key 둘 다 필요하다")
            }
            do { try config.save(root: root) } catch { fail("저장 실패: \(error.localizedDescription)") }
            print(CLILocalization.format("CommandGujo.print-13", GujoBlobConfig.fileURL(root: root).path))
        } else {
            print("endpoint \(config.endpoint)")
            print("bucket   \(config.bucket)  region \(config.region)")
            print(CLILocalization.format("CommandGujo.print-14", config.accessKey.isEmpty ? CLILocalization.string("cli.unset") : String(config.accessKey.prefix(6)) + "…"))
            print(CLILocalization.format("CommandGujo.print-15", config.secretKey.isEmpty ? CLILocalization.string("cli.auto2") : CLILocalization.string("cli.auto9")))
        }
        return
    }

    guard let config = GujoBlobConfig.load(root: root) else {
        fail("""
        blob 자격이 없다 — 다음 중 하나로 설정:
          agent-wiki gujo blob config --access-key <GK…> --secret-key <…>
          env GUJO_S3_ACCESS_KEY / GUJO_S3_SECRET_KEY
        (자격 발급: Cloudflare 대시보드 R2 API 토큰 — s3-storage-manager 「테넌트 관리」로 등록·회전 관리)
        """)
    }
    let blob = GujoBlobSync(root: root, config: config)
    let requested: [String]? = {
        let shas = CLIArgv.positionals(
            in: arguments, startingAt: 3, optionsWithValues: ["--root"])
        return shas.isEmpty ? nil : shas
    }()

    switch action {
    case "status":
        switch blob.plan() {
        case .failure(let error): fail("blob status 실패 — \(error.message)")
        case .success(let plan):
            emit(plan, json: json) {
                print(CLILocalization.format("CommandGujo.print-16", plan.localCount, plan.remoteCount))
                print(CLILocalization.format("CommandGujo.print-17", String(plan.missingLocal.count)))
                print(CLILocalization.format("CommandGujo.print-18", String(plan.missingRemote.count)))
            }
        }
    case "pull":
        switch blob.pull(shas: requested) {
        case .failure(let error): fail("blob pull 실패 — \(error.message)")
        case .success(let outcome):
            emit(outcome, json: json) {
                print(CLILocalization.format("CommandGujo.print-19", String(outcome.transferred.count), String(outcome.bytes), outcome.skipped, outcome.failed.count))
                for sha in outcome.failed { print(CLILocalization.format("CommandGujo.print-20", sha)) }
            }
            if !outcome.failed.isEmpty { exit(1) }
        }
    case "push":
        switch blob.push(shas: requested) {
        case .failure(let error): fail("blob push 실패 — \(error.message)")
        case .success(let outcome):
            emit(outcome, json: json) {
                print(CLILocalization.format("CommandGujo.print-21", String(outcome.transferred.count), String(outcome.bytes), outcome.failed.count))
                for sha in outcome.failed { print(CLILocalization.format("CommandGujo.print-20", sha)) }
            }
            if !outcome.failed.isEmpty { exit(1) }
        }
    default:
        fail("gujo blob <status|pull|push|config>")
    }
}
