import Foundation

/// 파일의 `(path, mtime, size, fingerprint)`를 마이크로초 단위로 기록·검증하는 2-Tier Stat 캐시 엔진.
///
/// Tier 1: In-Memory 스레드 안전 딕셔너리 (`NSLock`)
/// Tier 2: On-Disk JSON 캐시 파일 (원자적 영속화)
public final class StatCacheOracle: @unchecked Sendable {

    public struct Entry: Codable, Sendable {
        public let mtimeSec: Int64
        public let mtimeNsec: Int64
        public let size: Int64
        public let fingerprint: Int
        public let payload: Data

        public init(mtimeSec: Int64, mtimeNsec: Int64, size: Int64, fingerprint: Int, payload: Data = Data()) {
            self.mtimeSec = mtimeSec
            self.mtimeNsec = mtimeNsec
            self.size = size
            self.fingerprint = fingerprint
            self.payload = payload
        }
    }

    private let lock = NSLock()
    private var memoryCache: [String: Entry] = [:]
    private var isDirty = false
    public let cacheFileURL: URL?

    public init(cacheFileURL: URL?) {
        self.cacheFileURL = cacheFileURL
        loadFromDisk()
    }

    public convenience init(root: String, cacheFileName: String = "stat-cache.json") {
        let fm = FileManager.default
        let buildDir = URL(fileURLWithPath: root).appendingPathComponent(".build")
        if !fm.fileExists(atPath: buildDir.path) {
            do { try fm.createDirectory(at: buildDir, withIntermediateDirectories: true) } catch { _ = error }
        }
        let url = buildDir.appendingPathComponent(cacheFileName)
        self.init(cacheFileURL: url)
    }

    private func loadFromDisk() {
        guard let url = cacheFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        memoryCache = decoded
    }

    public func flush() {
        guard let url = cacheFileURL else { return }
        let snapshot: [String: Entry]
        lock.lock()
        guard isDirty else {
            lock.unlock()
            return
        }
        snapshot = memoryCache
        isDirty = false
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // 캐시 영속화 실패는 도메인 실행에 영향을 주지 않고 무시
        }
    }

    /// 파일의 현재 stat (mtime, size) 및 fingerprint가 캐시와 일치하는지 확인.
    /// 일치하면 저장된 payload Data 반환, 불일치 시 nil 반환.
    public func lookup(path: String, root: String, fingerprint: Int) -> Data? {
        let absPath = path.hasPrefix("/") ? path : (root + "/" + path)
        var st = stat()
        guard stat(absPath, &st) == 0 else { return nil }

        #if os(macOS)
        let mtimeSec = Int64(st.st_mtimespec.tv_sec)
        let mtimeNsec = Int64(st.st_mtimespec.tv_nsec)
        #else
        let mtimeSec = Int64(st.st_mtim.tv_sec)
        let mtimeNsec = Int64(st.st_mtim.tv_nsec)
        #endif
        let size = Int64(st.st_size)

        lock.lock()
        defer { lock.unlock() }

        guard let entry = memoryCache[path] else { return nil }
        if entry.size == size &&
           entry.mtimeSec == mtimeSec &&
           entry.mtimeNsec == mtimeNsec &&
           entry.fingerprint == fingerprint {
            return entry.payload
        }
        return nil
    }

    /// 파일 검사 또는 처리 완료 후 결과 stat 및 payload 기록.
    public func record(path: String, root: String, fingerprint: Int, payload: Data = Data()) {
        let absPath = path.hasPrefix("/") ? path : (root + "/" + path)
        var st = stat()
        guard stat(absPath, &st) == 0 else { return }

        #if os(macOS)
        let mtimeSec = Int64(st.st_mtimespec.tv_sec)
        let mtimeNsec = Int64(st.st_mtimespec.tv_nsec)
        #else
        let mtimeSec = Int64(st.st_mtim.tv_sec)
        let mtimeNsec = Int64(st.st_mtim.tv_nsec)
        #endif
        let size = Int64(st.st_size)

        let entry = Entry(
            mtimeSec: mtimeSec,
            mtimeNsec: mtimeNsec,
            size: size,
            fingerprint: fingerprint,
            payload: payload
        )

        lock.lock()
        defer { lock.unlock() }
        memoryCache[path] = entry
        isDirty = true
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        memoryCache.removeAll()
        isDirty = true
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache.count
    }
}
