
private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let src = DispatchSource.makeTimerSource()
    src.schedule(deadline: .now() + seconds)
    src.setEventHandler { process.terminate() }
    src.resume()
    process.waitUntilExit()
    src.cancel()
}
import Foundation
import KnowledgeBaseWikiCore

/// 원본층 blob 조종 — content-addressed 저장소(<root>/blobs). 정본이지만 대용량이라
/// 사건 로그가 sha 로만 가리킨다. put 은 stdin 또는 파일, get 은 stdout.
public func runBlob(root: URL, arguments: [String]) {
    let store = BlobStore(root: root)
    let sub = arguments.count >= 2 ? arguments[1] : "list"
    switch sub {
    case "put":     blobPut(store: store, arguments: arguments)
    case "get":     blobGet(store: store, arguments: arguments)
    case "path":    blobPath(store: store, arguments: arguments)
    case "info":    blobInfo(store: store, root: root, arguments: arguments)
    case "open":    blobOpen(store: store, arguments: arguments)
    case "refs":    blobRefs(root: root, arguments: arguments)
    case "verify":  blobVerify(store: store, arguments: arguments)
    case "list":    blobList(store: store)
    case "gc":      blobGC(store: store, root: root, arguments: arguments)
    default:        fail(usage)
    }
}

private func blobPut(store: BlobStore, arguments: [String]) {
    let data: Data
    if arguments.count >= 3 {
        let d: Data
        do { d = try Data(contentsOf: URL(fileURLWithPath: arguments[2])) }
        catch { fail("blob put: 파일 읽기 실패 \(arguments[2]): \(error.localizedDescription)") }
        data = d
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    let sha: String
    do { sha = try store.put(data) } catch { fail("blob put: 저장 실패: \(error.localizedDescription)") }
    print(sha) // allow:debug
}

private func blobGet(store: BlobStore, arguments: [String]) {
    guard arguments.count >= 3 else { fail("blob get <sha>") }
    guard let data = store.get(arguments[2]) else { fail("blob get: 없음 \(arguments[2])", code: 1) }
    FileHandle.standardOutput.write(data)
}

private func blobPath(store: BlobStore, arguments: [String]) {
    guard arguments.count >= 3 else { fail("blob path <sha>") }
    print(store.url(for: arguments[2]).path) // allow:debug
}

private func blobInfo(store: BlobStore, root: URL, arguments: [String]) {
    guard arguments.count >= 3 else { fail("blob info <sha>") }
    let sha = arguments[2]
    guard let kind = store.kind(sha) else { fail("blob info: 없음 \(sha)", code: 1) }
    let size = store.size(sha) ?? 0
    let refs = EventLog(root: root).eventsReferencing(blob: sha)
    print("종류: \(kind.label)  크기: \(size) B  무결성: \(store.verify(sha) ? "OK" : "변조!")") // allow:debug
    print("연결된 사건 \(refs.count)건:") // allow:debug
    for e in refs {
        print("  \(ISO8601DateFormatter().string(from: e.occurred))  [\(e.rel)] \(e.subject.prefix(8))  (\(e.writer))") // allow:debug
    }
}

private func blobOpen(store: BlobStore, arguments: [String]) {
    guard arguments.count >= 3 else { fail("blob open <sha>") }
    let sha = arguments[2]
    guard let data = store.get(sha), let kind = store.kind(sha) else { fail("blob open: 없음 \(sha)", code: 1) }
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("blob-\(sha.prefix(12)).\(kind.ext)")
    do {
        try data.write(to: tmp)
        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = [tmp.path]
        waitWithTimeout(p)
        print("열기(\(kind.label)): \(tmp.path)") // allow:debug
    } catch { fail("blob open 실패: \(error)") }
}

private func blobRefs(root: URL, arguments: [String]) {
    guard arguments.count >= 3 else { fail("blob refs <sha|접두어>") }
    let index = LedgerIndex(root: root)
    index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
    let sha = index.resolveBlobSHA(arguments[2]) ?? arguments[2]
    let objects = index.objectsReferencing(blob: sha)
    let events = EventLog(root: root).eventsReferencing(blob: sha)
    if objects.isEmpty && events.isEmpty { print("(참조 없음 — gc 회수 대상)") } // allow:debug
    for r in objects {
        let mark = r.via == "typed" ? "typed" : "본문"
        print("객체 \(r.object.prefix(8))  [\(mark)] \(r.title ?? "(무제)")") // allow:debug
    }
    for e in events {
        print("사건 \(ISO8601DateFormatter().string(from: e.occurred))  [\(e.rel)] \(e.subject.prefix(8))  (\(e.writer))") // allow:debug
    }
}

private func blobVerify(store: BlobStore, arguments: [String]) {
    let targets = arguments.count >= 3 ? [arguments[2]] : store.allSHAs()
    var bad = 0
    for sha in targets where !store.verify(sha) { bad += 1; print("변조/누락: \(sha)") } // allow:debug
    if bad == 0 { print("blob 이상 없음 (\(targets.count)개)") } else { fail("\(bad)개 변조/누락", code: 2) } // allow:debug
}

private func blobList(store: BlobStore) {
    let all = store.allSHAs()
    for sha in all { print(sha) } // allow:debug
    FileHandle.standardError.write(Data("총 \(all.count)개 blob\n".utf8))
}

private func blobGC(store: BlobStore, root: URL, arguments: [String]) {
    let gcIndex = LedgerIndex(root: root)
    gcIndex.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
    var reachable = EventLog(root: root).reachableBlobSHAs()
    reachable.formUnion(gcIndex.referencedBlobSHAs())
    let onDisk = store.allSHAs()
    let doomed = onDisk.filter { !reachable.contains($0) }
    guard !doomed.isEmpty else {
        print("blob gc: 제거할 것 없음 (\(onDisk.count)개 전부 참조됨)") // allow:debug
        return
    }
    let freed = doomed.reduce(0) { $0 + (store.size($1) ?? 0) }
    guard arguments.contains("--apply") else {
        printGCPreview(doomed: doomed, freed: freed, reachable: reachable, store: store)
        return
    }
    let removed = store.prune(keeping: reachable)
    print("blob gc: \(removed)개 제거, \(store.allSHAs().count)개 유지 (참조 \(reachable.count)개)") // allow:debug
}

private func printGCPreview(doomed: [String], freed: Int, reachable: Set<String>, store: BlobStore) {
    print("blob gc (미리보기): \(doomed.count)개 · \(freed) B 제거 예정, " // allow:debug
        + "\(reachable.count)개 유지")
    for sha in doomed.prefix(20) { print("  \(sha.prefix(12))  \(store.size(sha) ?? 0) B") } // allow:debug
    if doomed.count > 20 { print("  … \(doomed.count - 20)개 더") } // allow:debug
    print("실제로 지우려면: blob gc --apply") // allow:debug
}
