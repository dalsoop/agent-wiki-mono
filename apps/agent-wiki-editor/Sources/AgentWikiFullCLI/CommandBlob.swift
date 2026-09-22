
import Foundation
import KnowledgeBaseWikiCore
import CommandKit
import LocalizationKit

/// 원본층 blob 조종 — content-addressed 저장소(<root>/blobs). 정본이지만 대용량이라
/// 사건 로그가 sha 로만 가리킨다. put 은 stdin 또는 파일, get 은 stdout.
func runBlob(root: URL, arguments: [String]) {
    let store = BlobStore(root: root)
    let sub = arguments.count >= 2 ? arguments[1] : "list"
    switch sub {
    case "put":
        // blob put [<파일>]  — 파일 없으면 stdin
        let data: Data
        if arguments.count >= 3 {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: arguments[2])) else {
                fail("blob put: 파일 읽기 실패 \(arguments[2])")
            }
            data = d
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let sha = try? store.put(data) else { fail("blob put: 저장 실패") }
        print(sha)

    case "get":
        // blob get <sha>  → stdout
        guard arguments.count >= 3 else { fail("blob get <sha>") }
        guard let data = store.get(arguments[2]) else { fail("blob get: 없음 \(arguments[2])", code: 1) }
        FileHandle.standardOutput.write(data)

    case "path":
        guard arguments.count >= 3 else { fail("blob path <sha>") }
        print(store.url(for: arguments[2]).path)

    case "info":
        // 종류·크기·연결(역참조) — 원본이 뭐고 무엇에 연결됐나.
        guard arguments.count >= 3 else { fail("blob info <sha>") }
        let sha = arguments[2]
        guard let kind = store.kind(sha) else { fail("blob info: 없음 \(sha)", code: 1) }
        let size = store.size(sha) ?? 0
        let refs = EventLog(root: root).eventsReferencing(blob: sha)
        print(CLILocalization.format("CommandBlob.print", kind.label, size, store.verify(sha) ? "OK" : CLILocalization.string("cli.tampered")))
        print(CLILocalization.format("CommandBlob.print-2", refs.count))
        for e in refs {
            print("  \(ISO8601DateFormatter().string(from: e.occurred))  [\(e.rel)] \(e.subject.prefix(8))  (\(e.writer))")
        }

    case "open":
        // 기본 앱으로 열기 — 임시 파일에 원본 확장자로 쓰고 open(1). PDF·MP3 등을 실제로 본다.
        guard arguments.count >= 3 else { fail("blob open <sha>") }
        let sha = arguments[2]
        guard let data = store.get(sha), let kind = store.kind(sha) else { fail("blob open: 없음 \(sha)", code: 1) }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("blob-\(sha.prefix(12)).\(kind.ext)")
        do {
            try data.write(to: tmp)
            // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
            let safeResult = SafeProcessRunner.run(
                "/usr/bin/open",
                []
            )
            print(CLILocalization.format("CommandBlob.print-3", kind.label, tmp.path))
        } catch { fail("blob open 실패: \(error)") }

    case "refs":
        // 역참조 — 이 원본을 가리키는 **객체와 사건** 둘 다.
        // 예전엔 사건만 봤다. 그래서 md 객체가 그림으로 안고 있는 원본이 "참조 없음"
        // 으로 보였고, 같은 정의를 쓰던 gc 가 그걸 회수 대상으로 삼았다.
        guard arguments.count >= 3 else { fail("blob refs <sha|접두어>") }
        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
        // 접두어 허용 — 다른 명령은 다 받는데 이것만 전체 sha 를 요구해 "참조 없음"
        // 으로 오독하게 만들었다(실측 오진 2026-08-04).
        let sha = index.resolveBlobSHA(arguments[2]) ?? arguments[2]
        let objects = index.objectsReferencing(blob: sha)
        let events = EventLog(root: root).eventsReferencing(blob: sha)
        if objects.isEmpty && events.isEmpty { print(CLILocalization.string("CommandBlob.print-4")) }
        for r in objects {
            let mark = r.via == "typed" ? "typed" : "본문"
            print(CLILocalization.format("CommandBlob.print-5", String(r.object.prefix(8)), mark, r.title ?? CLILocalization.string("cli.untitled")))
        }
        for e in events {
            print(CLILocalization.format("CommandBlob.print-6", ISO8601DateFormatter().string(from: e.occurred), e.rel, String(e.subject.prefix(8)), e.writer))
        }

    case "verify":
        // blob verify [<sha>]  — 인자 있으면 그것만, 없으면 전체
        let targets = arguments.count >= 3 ? [arguments[2]] : store.allSHAs()
        var bad = 0
        for sha in targets where !store.verify(sha) { bad += 1; print(CLILocalization.format("CommandBlob.print-7", sha)) }
        if bad == 0 { print(CLILocalization.format("CommandBlob.print-8", targets.count)) } else { fail(CLILocalization.format("cli.bad-count", String(bad)), code: 2) }

    case "list":
        let all = store.allSHAs()
        for sha in all { print(sha) }
        FileHandle.standardError.write(Data("총 \(all.count)개 blob\n".utf8))

    case "gc":
        // 참조되지 않는 blob 제거(git gc 식). **reachable 을 사건 source 만으로 잡으면
        // 안 된다** — md 객체가 가리키는 원본이 통째로 회수 대상이 되고, blob 은 정본이라
        // 복구할 길이 없다. 실측(2026-08-04): 사건만 셌을 때 36개 중 26개(12.2 MB)가
        // 삭제 대상이었고 그 26개 전부를 md 객체가 참조하고 있었다.
        //
        // 그래서 세 경로를 모두 산다:
        //   ① 사건 source          기계 참조
        //   ② 객체 source.blob     기계 참조(정식 경로)
        //   ③ 객체 본문의 sha      사람이 적은 참조 — 타입은 없지만 지우면 안 된다
        // ③ 을 포함하는 건 관대해서가 아니라, 회수의 기본값이 "의심스러우면 남긴다"
        // 여야 하기 때문이다. ③ 을 ② 로 옮기는 건 `structure` 가 세어 보여준다.
        // 도달성 정의는 **색인 한 곳**에서 온다 — CLI·구조 화면·gc 가 갈라지지 않게.
        let gcIndex = LedgerIndex(root: root)
        gcIndex.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
        var reachable = EventLog(root: root).reachableBlobSHAs()
        reachable.formUnion(gcIndex.referencedBlobSHAs())
        let onDisk = store.allSHAs()
        let doomed = onDisk.filter { !reachable.contains($0) }
        guard !doomed.isEmpty else {
            print(CLILocalization.format("CommandBlob.print-9", onDisk.count))
            return
        }
        let freed = doomed.reduce(0) { $0 + (store.size($1) ?? 0) }
        // 되돌릴 수 없는 삭제라 기본은 미리보기다. 실제 제거는 --apply 를 요구한다.
        guard arguments.contains("--apply") else {
            print(CLILocalization.format("CommandBlob.print-10", doomed.count, freed)
                + "\(reachable.count)개 유지")
            for sha in doomed.prefix(20) { print("  \(sha.prefix(12))  \(store.size(sha) ?? 0) B") }
            if doomed.count > 20 { print(CLILocalization.format("CommandBlob.print-11", String(doomed.count - 20))) }
            print(CLILocalization.string("CommandBlob.print-12"))
            return
        }
        let removed = store.prune(keeping: reachable)
        print(CLILocalization.format("CommandBlob.print-13", removed, store.allSHAs().count, reachable.count))

    default:
        fail(usage)
    }
}
