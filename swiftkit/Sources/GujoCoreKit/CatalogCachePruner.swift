import FastDiskIOKit
import Foundation

/// 카탈로그 렌더 캐시(`products/<id>/`)의 보존 정책.
///
/// `LibraryController.renderDetail/renderThumbnail` 가 제품별 캐시 디렉터리를 만들지만
/// 서버 카탈로그에서 제품이 사라져도 지우는 경로가 없어 디스크(그리고 app-saves 미러)에
/// 남는다. 이 프루너는 라이브 카탈로그의 제품 ID 집합을 정본으로 삼아, 거기 없는
/// 제품의 캐시 디렉터리를 정리한다. 판정은 제품(디렉터리) 단위다 — 렌더 자산은
/// 언제든 서버에서 다시 받을 수 있어 파일 단위 고아 추적은 불필요하다.
///
/// 안전 규칙:
/// - 정수 이름 디렉터리만 본다. 설치 슬러그(`12-my-app`)처럼 우리 캐시와 다른
///   형태의 디렉터리는 라이브 여부와 무관하게 절대 건드리지 않는다.
/// - 라이브 집합이 비면 아무것도 지우지 않는다(부분 응답·실패한 목록으로
///   유효한 캐시를 몰아내는 사고 방지).
/// - 삭제 실패는 보고서에 실어 돌려준다. 부분 성공을 throw 로 묻지 않는다.
public enum CatalogCachePruner {

    /// 프루닝 결과. dry-run(예정)과 실행(결과)을 같은 형태로 표현한다.
    public struct Report: Codable, Sendable, Equatable {
        /// true 면 아무것도 지우지 않은 예정 보고서.
        public var dryRun: Bool
        /// 정본 카탈로그가 가진 제품 수.
        public var liveProductCount: Int
        /// 정리 대상(또는 정리된) 제품 ID. 오름차순.
        public var removedProductIDs: [Int]
        /// 회수(예정) 바이트 수.
        public var freedBytes: Int64
        /// 삭제에 실패한 제품 ID.
        public var failedProductIDs: [Int]
        /// 마지막 실패 사유(실패가 있을 때).
        public var failureMessage: String?
        /// 프루닝을 건너뛴 사유(예: 라이브 집합 비었음).
        public var skippedReason: String?

        public init(
            dryRun: Bool,
            liveProductCount: Int,
            removedProductIDs: [Int] = [],
            freedBytes: Int64 = 0,
            failedProductIDs: [Int] = [],
            failureMessage: String? = nil,
            skippedReason: String? = nil
        ) {
            self.dryRun = dryRun
            self.liveProductCount = liveProductCount
            self.removedProductIDs = removedProductIDs
            self.freedBytes = freedBytes
            self.failedProductIDs = failedProductIDs
            self.failureMessage = failureMessage
            self.skippedReason = skippedReason
        }

        /// 화면·CLI 요약용: 정리 대상이 없다.
        public var hasWork: Bool { !removedProductIDs.isEmpty }
    }

    /// 캐시 디렉터리에서 정수 이름의 제품 ID 만을 뽑는다. 나머지 이름은 우리 캐시가
    /// 아니므로 무시한다(설치 슬러그 등). 상태 미러·설정 화면 요약에도 쓴다.
    public static func cachedProductIDs(in productsDir: URL) -> [Int] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: productsDir.path) else { return [] }
        return names.compactMap { Int($0) }
    }

    private static func directorySize(_ dir: URL) -> Int64 {
        let entries = FastDirectoryScanner.scanEntries(in: dir.path, skipping: [])
        return entries.reduce(0) { total, entry in
            entry.isDirectory ? total : total + entry.size
        }
    }

    /// 라이브 카탈로그 기준으로 `products/` 를 정리한다.
    ///
    /// - Parameters:
    ///   - liveProductIDs: 서버 카탈로그에 있는 제품 ID 집합.
    ///   - productsDir: `AppPaths.productsDir`.
    ///   - dryRun: true 면 무엇을 지울지만 계산한다.
    /// - Returns: 예정(dry-run) 또는 실행 결과 보고서.
    public static func prune(liveProductIDs: Set<Int>, productsDir: URL, dryRun: Bool) -> Report {
        let fm = FileManager.default
        guard fm.fileExists(atPath: productsDir.path) else {
            return Report(dryRun: dryRun, liveProductCount: liveProductIDs.count)
        }
        guard !liveProductIDs.isEmpty else {
            return Report(
                dryRun: dryRun, liveProductCount: 0,
                skippedReason: "empty-catalog")
        }
        let orphans = cachedProductIDs(in: productsDir)
            .filter { !liveProductIDs.contains($0) }
            .sorted()

        guard !orphans.isEmpty else {
            return Report(dryRun: dryRun, liveProductCount: liveProductIDs.count)
        }

        var report = Report(dryRun: dryRun, liveProductCount: liveProductIDs.count)
        for id in orphans {
            let dir = productsDir.appendingPathComponent(String(id), isDirectory: true)
            report.freedBytes += directorySize(dir)
            guard !dryRun else { continue }
            do {
                try fm.removeItem(at: dir)
                report.removedProductIDs.append(id)
            } catch {
                report.failedProductIDs.append(id)
                report.failureMessage = error.localizedDescription
            }
        }
        if dryRun {
            report.removedProductIDs = orphans
        } else {
            report.removedProductIDs.sort()
        }
        return report
    }
}

/// 마지막으로 성공한 카탈로그 응답의 제품 ID 목록 — 프루닝의 오프라인 정본.
///
/// GUI 가 리프레시마다 쓰고, CLI(`gujo cache-prune`)와 수동 정리가 자격 없이도
/// 같은 판정을 하도록 읽는다. 파일이 없으면 아직 한 번도 로그인하지 않은 것이다.
public struct CatalogLiveManifest: Codable, Sendable, Equatable {
    public var productIDs: [Int]
    public var generatedAt: Date

    public init(productIDs: [Int], generatedAt: Date = Date()) {
        self.productIDs = productIDs
        self.generatedAt = generatedAt
    }

    public var liveProductIDs: Set<Int> { Set(productIDs) }
}

public enum CatalogLiveManifestStore {
    public static let fileName = "catalog-live.json"

    public static func fileURL(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    /// 기본 위치 — `~/Library/Application Support/Gujo/catalog-live.json`.
    public static var defaultFileURL: URL { fileURL(in: AppPaths.support) }

    /// 원자적 쓰기. 최신 카탈로그가 부분 쓰기로 보이는 일이 없게 한다.
    public static func save(_ manifest: CatalogLiveManifest, to url: URL = defaultFileURL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    /// 파일이 없으면 nil. 파손되면 nil(프루너가 빈 집합을 믿고 지우는 사고 방지).
    public static func load(from url: URL = defaultFileURL) -> CatalogLiveManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CatalogLiveManifest.self, from: data)
    }
}
