import Foundation
import FastDiskIOKit

/// 캐시된 린트 위반 단일 건
public struct CachedFinding: Codable, Sendable, Equatable {
    public let ruleID: String
    public let line: Int
    public let message: String
    public let severity: String

    public init(ruleID: String, line: Int, message: String, severity: String = "error") {
        self.ruleID = ruleID
        self.line = line
        self.message = message
        self.severity = severity
    }
}

/// 캐시된 파일 린트 검사 결과
public struct CachedLintResult: Codable, Sendable, Equatable {
    public let cacheKey: String
    public let filePath: String
    public let rulesDigest: String
    public let fileContentSHA256: String
    public let violationCount: Int
    public let findings: [CachedFinding]
    public let cachedAt: Date

    public init(
        cacheKey: String,
        filePath: String,
        rulesDigest: String,
        fileContentSHA256: String,
        violationCount: Int,
        findings: [CachedFinding],
        cachedAt: Date = Date()
    ) {
        self.cacheKey = cacheKey
        self.filePath = filePath
        self.rulesDigest = rulesDigest
        self.fileContentSHA256 = fileContentSHA256
        self.violationCount = violationCount
        self.findings = findings
        self.cachedAt = cachedAt
    }
}

/// 파일 메타데이터 서명 (mtime 및 크기)
public struct FileSignature: Sendable, Equatable {
    public let mtimeSec: Int64
    public let mtimeNsec: Int64
    public let fileSize: Int64

    public init(mtimeSec: Int64, mtimeNsec: Int64, fileSize: Int64) {
        self.mtimeSec = mtimeSec
        self.mtimeNsec = mtimeNsec
        self.fileSize = fileSize
    }
}

/// 캐시 조회 적중 단계
public enum HitStage: String, Sendable, Codable {
    case l1Mtime = "L1_MTIME"
    case l2ContentHash = "L2_CONTENT_HASH"
}

/// 캐시 조회 결과
public enum CacheLookupResult: Sendable {
    case hit(CachedLintResult, HitStage)
    case miss(fileContentSHA256: String, compositeKey: String)
}

/// SHA256(RulesDigest + FileContentSHA256) 기반 2단계 결과 캐시.
/// - Stage 1 (L1 In-Memory mtime/size): 파일 수정시간 및 크기 일치 시 디스크 I/O 없이 0ms 즉시 통과.
/// - Stage 2 (L2 Content-Hash CAS): mtime 변경/재체크아웃 시에도 콘텐츠 해시와 룰 다이제스트 일치 시 린트 재실행 0ms 스킵.
public actor ContentHashCache {

    private struct L1Entry: Sendable {
        let signature: FileSignature
        let rulesDigest: String
        let cacheKey: String
    }

    /// 파일 경로 -> L1 파일 서명 매핑
    private var l1Signatures: [String: L1Entry] = [:]

    /// compositeKey -> 캐시된 린트 결과 (메모리 L2)
    private var l2Results: [String: CachedLintResult] = [:]

    /// 디스크 캐시 루트 디렉터리 (nil 일 경우 인메모리 전용)
    private let diskCacheDirectory: URL?
    private let maxMemoryEntries: Int

    public init(diskCacheDirectory: URL? = nil, maxMemoryEntries: Int = 50_000) {
        self.diskCacheDirectory = diskCacheDirectory
        self.maxMemoryEntries = maxMemoryEntries
        if let dir = diskCacheDirectory {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch let error {
                _ = error // 디스크 캐시 디렉터리 생성 실패 시 인메모리 폴백
            }
        }
    }

    /// 캐시 키 생성: SHA256(RulesDigest + FileContentSHA256)
    @inlinable
    public static func computeCacheKey(rulesDigest: String, fileContentSHA256: String) -> String {
        FastSHA256.hash(string: "\(rulesDigest):\(fileContentSHA256)")
    }

    /// 2단계 캐시 조회
    /// - Parameters:
    ///   - filePath: 대상 파일 절대/상대 경로
    ///   - rulesDigest: 현재 적용 대상 룰셋 전체의 해시 다이제스트
    /// - Returns: 적중 시 CachedLintResult, 미적중 시 (fileContentSHA256, compositeKey)
    public func lookup(filePath: String, rulesDigest: String) throws -> CacheLookupResult {
        var statInfo = stat()
        guard stat(filePath, &statInfo) == 0 else {
            throw CocoaError(.fileNoSuchFile)
        }

        #if os(macOS) || os(iOS)
        let mtimeSec = Int64(statInfo.st_mtimespec.tv_sec)
        let mtimeNsec = Int64(statInfo.st_mtimespec.tv_nsec)
        #else
        let mtimeSec = Int64(statInfo.st_mtim.tv_sec)
        let mtimeNsec = Int64(statInfo.st_mtim.tv_nsec)
        #endif
        let currentSig = FileSignature(mtimeSec: mtimeSec, mtimeNsec: mtimeNsec, fileSize: Int64(statInfo.st_size))

        // -------------------------------------------------------------
        // Stage 1: Fast L1 Memory mtime/size check (< 0.01ms)
        // -------------------------------------------------------------
        if let l1 = l1Signatures[filePath],
           l1.rulesDigest == rulesDigest,
           l1.signature == currentSig,
           let cached = l2Results[l1.cacheKey] {
            return .hit(cached, .l1Mtime)
        }

        // -------------------------------------------------------------
        // Stage 2: Content-Hash Lookup (SHA256 of content)
        // -------------------------------------------------------------
        return try lookupStage2(filePath: filePath, currentSig: currentSig, rulesDigest: rulesDigest)
    }

    private func lookupStage2(filePath: String, currentSig: FileSignature, rulesDigest: String) throws -> CacheLookupResult {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let contentSHA256 = FastSHA256.hash(data: fileData)
        let compositeKey = Self.computeCacheKey(rulesDigest: rulesDigest, fileContentSHA256: contentSHA256)

        // 1) L2 메모리 캐시 확인
        if let cached = l2Results[compositeKey] {
            recordL1(filePath: filePath, signature: currentSig, rulesDigest: rulesDigest, cacheKey: compositeKey)
            return .hit(cached, .l2ContentHash)
        }

        // 2) 디스크 CAS 영속 저장소 확인
        if let diskResult = loadFromDisk(cacheKey: compositeKey) {
            l2Results[compositeKey] = diskResult
            recordL1(filePath: filePath, signature: currentSig, rulesDigest: rulesDigest, cacheKey: compositeKey)
            return .hit(diskResult, .l2ContentHash)
        }

        // Cache Miss
        return .miss(fileContentSHA256: contentSHA256, compositeKey: compositeKey)
    }

    /// 린트 결과 저장 (Stage 1 및 Stage 2 동시 적재)
    @discardableResult
    public func store(
        filePath: String,
        rulesDigest: String,
        fileContentSHA256: String,
        findings: [CachedFinding]
    ) throws -> CachedLintResult {
        let compositeKey = Self.computeCacheKey(rulesDigest: rulesDigest, fileContentSHA256: fileContentSHA256)
        let result = CachedLintResult(
            cacheKey: compositeKey,
            filePath: filePath,
            rulesDigest: rulesDigest,
            fileContentSHA256: fileContentSHA256,
            violationCount: findings.count,
            findings: findings
        )

        // L2 메모리 저장
        l2Results[compositeKey] = result

        // L1 서명 저장
        var statInfo = stat()
        if stat(filePath, &statInfo) == 0 {
            #if os(macOS) || os(iOS)
            let mtimeSec = Int64(statInfo.st_mtimespec.tv_sec)
            let mtimeNsec = Int64(statInfo.st_mtimespec.tv_nsec)
            #else
            let mtimeSec = Int64(statInfo.st_mtim.tv_sec)
            let mtimeNsec = Int64(statInfo.st_mtim.tv_nsec)
            #endif
            let sig = FileSignature(mtimeSec: mtimeSec, mtimeNsec: mtimeNsec, fileSize: Int64(statInfo.st_size))
            recordL1(filePath: filePath, signature: sig, rulesDigest: rulesDigest, cacheKey: compositeKey)
        }

        // 디스크 영속 저장 (설정된 경우 원자적 기록)
        try saveToDisk(result: result)

        pruneMemoryIfNeeded()
        return result
    }

    private func recordL1(filePath: String, signature: FileSignature, rulesDigest: String, cacheKey: String) {
        l1Signatures[filePath] = L1Entry(signature: signature, rulesDigest: rulesDigest, cacheKey: cacheKey)
    }

    private func pruneMemoryIfNeeded() {
        if l2Results.count > maxMemoryEntries {
            l2Results.removeAll(keepingCapacity: true)
            l1Signatures.removeAll(keepingCapacity: true)
        }
    }

    private func diskFilePath(for cacheKey: String) -> URL? {
        guard let base = diskCacheDirectory else { return nil }
        let prefix = String(cacheKey.prefix(2))
        let subDir = base.appendingPathComponent(prefix, isDirectory: true)
        return subDir.appendingPathComponent("\(cacheKey).json")
    }

    private func loadFromDisk(cacheKey: String) -> CachedLintResult? {
        guard let url = diskFilePath(for: cacheKey) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedLintResult.self, from: data)
    }

    private func saveToDisk(result: CachedLintResult) throws {
        guard let url = diskFilePath(for: result.cacheKey) else { return }
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(result)
        try FastAtomicWriter.writeIfChanged(to: url.path, data: data)
    }

    public func clear() {
        l1Signatures.removeAll()
        l2Results.removeAll()
    }
}
