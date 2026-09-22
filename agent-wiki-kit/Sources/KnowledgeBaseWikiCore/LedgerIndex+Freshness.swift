import Foundation

extension LedgerIndex {
    // MARK: - 신선도

    /// objects/ 의 실제 md 파일 수(파싱 없이 열거만). append-only 신선도 판정용.
    public func diskObjectCount(objectsDir: URL) -> Int {
        guard let en = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
        var n = 0
        for case let url as URL in en where url.pathExtension == "md" { n += 1 }
        return n
    }

    /// 신선도 보장 — 발행은 추가만(불변·삭제 없음)이라 **개수가 다르면** 새 파일이 있는 것 → 증분 sync.
    /// 같으면 인덱스가 이미 최신이라 스캔 0. 흔한 경우(변경 없음) 파싱 0.
    public func ensureFresh(objectsDir: URL) {
        if isStale(objectsDir: objectsDir) {
            _ = sync(objectsDir: objectsDir)
        }
        // 원본층도 같이 따라오게 한다. blob 을 봉인만 하고 색인을 안 하면 검색이
        // 원문에 닿지 못한다 — objects 만 신선하게 유지하던 게 그 구멍이었다.
        let root = objectsDir.deletingLastPathComponent()
        if blobIndexIsStale(root: root) { _ = syncBlobs(root: root) }
    }

    /// blob 색인이 디스크보다 뒤처졌나 — sha 집합만 대조한다(내용은 불변이라 충분).
    public func blobIndexIsStale(root: URL) -> Bool {
        let onDisk = Set(BlobStore(root: root).allSHAs())
        var known: Set<String> = []
        db.prepared("SELECT sha FROM blobs;") { stmt in
            while stmt.step() { if let s = stmt.text(0) { known.insert(s) } }
        }
        return known != onDisk
    }

    /// 인덱스가 디스크보다 뒤처졌나. **개수 비교로는 부족하다** — 추가 1건과 삭제 1건이
    /// 겹치면 개수가 같아 stale 을 통과시키고, 제자리 개정도 못 잡는다. 최신 mtime 비교로
    /// 보강해봐도 두 변경이 같은 초에 일어나면 또 새는데, 그건 배치 작업에서 흔하다.
    ///
    /// 그래서 어림짐작 대신 **경로 집합과 (mtime, size) 를 그대로 대조한다.** 판정 비용은
    /// 디렉터리 열거 1회 + `files` 스캔 1회로, `sync` 가 어차피 하는 그 일이다(파싱은
    /// 바뀐 파일만 하므로 실제 비용은 sync 쪽에 남는다). 정확도를 어림값과 바꾸지 않는다.
    public func isStale(objectsDir: URL) -> Bool {
        var known: [String: Stat] = [:]
        db.prepared("SELECT path, mtime, size FROM files;") { stmt in
            while stmt.step() {
                known[stmt.text(0) ?? ""] = Stat(mtime: stmt.double(1), size: Int(stmt.int(2)))
            }
        }
        let disk = diskCensus(objectsDir: objectsDir)
        if disk.files.count != known.count { return true }
        for (path, stat) in disk.files {
            guard let k = known[path], k.mtime == stat.mtime, k.size == stat.size else { return true }
        }
        return false
    }

    /// objects/ 열거 1회로 경로별 (mtime, size). 파싱 없음 — 신선도 판정 전용.
    public func diskCensus(objectsDir: URL) -> (count: Int, files: [String: Stat]) {
        guard let en = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return (0, [:]) }
        var files: [String: Stat] = [:]
        for case let url as URL in en where url.pathExtension == "md" {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            files[url.path] = Stat(
                mtime: v?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                size: v?.fileSize ?? -1)
        }
        return (files.count, files)
    }
}
