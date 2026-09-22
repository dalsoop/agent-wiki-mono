import Foundation
import HTTPClientKit
import WebCrawlKit
import StateRootKit

/// 공고 상세의 한글 양식만 한 줄로 받는다. 재개·STOP·429 정지를 강제한다.
public struct BizInfoFormHarvester: Sendable {
    private let client: any HTTPClient
    private let pace: PolitePace
    public static let maxFileBytes = 15 * 1024 * 1024
    private static let blockedStatuses: Set<Int> = [403, 429, 503]
    private static let successStatusRange = 200..<400
    private static let maxConsecutiveBlocks = 3
    private static let maxFormsPerProgram = 8
    private static let blockBackoffSeconds = 45

    public var stateDir: URL { StateRootKit.url(".swift-app-state") }
    public var programsFile: URL { stateDir.appendingPathComponent("government-support-programs.json") }
    public var hwpInbox: URL { stateDir.appendingPathComponent("hwp-inbox") }
    public var harvestManifestFile: URL { stateDir.appendingPathComponent("bizinfo-form-harvest-manifest.json") }
    public var harvestProgressFile: URL { stateDir.appendingPathComponent("bizinfo-form-harvest-progress.json") }
    public var harvestStopFile: URL { stateDir.appendingPathComponent("bizinfo-form-harvest.stop") }
    public var lastMatchFile: URL { stateDir.appendingPathComponent("government-support-matcher-last.json") }

    public init(client: any HTTPClient = URLSessionHTTPClient(), pace: PolitePace = .standard) {
        self.client = client
        self.pace = pace
    }

    public func harvest(limit: Int? = nil, preferMatch: Bool = false, minScore: Int = 20) async -> HarvestReport {
        if !SourceSiteGate.isEnabled(id: "bizinfo") {
            return disabledReport()
        }
        FileLoad.ensureDirectory(hwpInbox)
        var progress = loadProgress()
        var manifest = loadManifest()
        var consecutiveBlocks = 0
        var reason: String?
        for (index, id) in nextIDs(limit: limit, preferMatch: preferMatch, minScore: minScore, visited: Set(progress.visited)).enumerated() {
            if FileManager.default.fileExists(atPath: harvestStopFile.path) {
                reason = "STOP 파일 — 수동 정지"
                break
            }
            if let stop = await visit(
                id: id, index: index,
                progress: &progress, manifest: &manifest,
                consecutiveBlocks: &consecutiveBlocks
            ) {
                reason = stop
                break
            }
        }
        return finish(progress: progress, manifest: manifest, reason: reason)
    }

    private func disabledReport() -> HarvestReport {
        HarvestReport(
            visited: loadProgress().visited.count,
            remaining: 0,
            downloadedFiles: loadProgress().downloadedFiles,
            programsWithHwp: 0,
            stoppedReason: "출처 원장에서 기업마당이 꺼져 있다",
            note: "government-support-source-sites enable --id bizinfo 후 harvest-forms"
        )
    }

    private func nextIDs(limit: Int?, preferMatch: Bool, minScore: Int, visited: Set<String>) -> [String] {
        let prefer: [String]
        if preferMatch, let data = FileLoad.data(contentsOf: lastMatchFile) {
            prefer = HarvestQueue.preferIDs(fromLastMatch: data, minScore: minScore)
        } else {
            prefer = []
        }
        let ids = HarvestQueue.nextIDs(catalogIDs: programIDs(), visited: visited, prefer: prefer)
        return Array(ids.prefix(limit ?? ids.count))
    }

    private func visit(
        id: String, index: Int,
        progress: inout HarvestProgress, manifest: inout HarvestManifest,
        consecutiveBlocks: inout Int
    ) async -> String? {
        do {
            try await Task.sleep(nanoseconds: pace.pageGapNanoseconds())
            if index > 0, index % max(pace.restEvery, 1) == 0 {
                try await Task.sleep(nanoseconds: pace.restNanoseconds())
            }
            try await collectForms(id: id, progress: &progress, manifest: &manifest)
            consecutiveBlocks = 0
            return nil
        } catch HarvestHalt.blocked(let status) {
            consecutiveBlocks += 1
            if consecutiveBlocks >= Self.maxConsecutiveBlocks {
                return "HTTP \(status) 차단"
            }
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.blockBackoffSeconds * consecutiveBlocks) * 1_000_000_000)
            } catch {
                return nil
            }
            return nil
        } catch {
            manifest.items.removeAll { $0.programID == id }
            manifest.items.append(HarvestItem(programID: id, files: [], skipped: [], error: error.localizedDescription))
            progress.visited.append(id)
            save(progress: progress, manifest: manifest)
            return nil
        }
    }

    private func collectForms(
        id: String,
        progress: inout HarvestProgress,
        manifest: inout HarvestManifest
    ) async throws {
        let detail = BizInfoEndpoints.detailURL(pblancId: id)
        let html = try await fetchText(detail, referer: BizInfoEndpoints.listingURL)
        let attachments = BizInfoAttachmentParser.parse(html: html)
        let forms = attachments.filter(\.isHangulForm)
        let skipped = attachments.filter { !$0.isHangulForm }.map(\.fileName)
        var files: [HarvestFile] = []
        for form in forms.prefix(Self.maxFormsPerProgram) {
            try await Task.sleep(nanoseconds: pace.fileGapNanoseconds())
            if let file = try await download(form, programID: id, referer: detail) {
                files.append(file)
            }
        }
        let item = HarvestItem(programID: id, files: files, skipped: skipped, error: nil)
        manifest.items.removeAll { $0.programID == id }
        manifest.items.append(item)
        patchCatalog(programID: id, files: files)
        progress.visited.append(id)
        progress.downloadedFiles += files.count
        save(progress: progress, manifest: manifest)
    }

    private func finish(
        progress: HarvestProgress,
        manifest: HarvestManifest,
        reason: String?
    ) -> HarvestReport {
        var progress = progress
        progress.stoppedReason = reason
        save(progress: progress, manifest: manifest)
        let withHwp = manifest.items.filter { !$0.files.isEmpty }.count
        let remaining = HarvestQueue.nextIDs(
            catalogIDs: programIDs(),
            visited: Set(progress.visited),
            prefer: []
        ).count
        return HarvestReport(
            visited: progress.visited.count,
            remaining: remaining,
            downloadedFiles: progress.downloadedFiles,
            programsWithHwp: withHwp,
            stoppedReason: reason,
            note: reason
                ?? "한글 양식만 받음. 재개: money-source-government-program-lookup harvest-forms. 정지: \(harvestStopFile.path) 파일 생성"
        )
    }

    public static func catalogProgramIDs() -> [String] {
        BizInfoFormHarvester().programIDs()
    }

    private func programIDs() -> [String] {
        guard let data = FileLoad.data(contentsOf: programsFile),
              let root = FileLoad.jsonObject(from: data) as? [String: Any],
              let rows = root["programs"] as? [[String: Any]] else { return [] }
        return rows.compactMap { $0["id"] as? String }
    }

    private func loadProgress() -> HarvestProgress {
        guard let data = FileLoad.data(contentsOf: harvestProgressFile),
              let decoded = FileLoad.decode(HarvestProgress.self, from: data) else {
            return HarvestProgress(visited: [], downloadedFiles: 0, stoppedReason: nil)
        }
        return decoded
    }

    private func loadManifest() -> HarvestManifest {
        guard let data = FileLoad.data(contentsOf: harvestManifestFile),
              let decoded = FileLoad.decode(HarvestManifest.self, from: data) else {
            return HarvestManifest(items: [])
        }
        return decoded
    }

    private func save(progress: HarvestProgress, manifest: HarvestManifest) {
        if let data = FileLoad.encode(progress) {
            FileLoad.write(data, to: harvestProgressFile)
        }
        if let data = FileLoad.encode(manifest) {
            FileLoad.write(data, to: harvestManifestFile)
        }
    }

    private func fetchText(_ url: URL, referer: URL) async throws -> String {
        let headers = [
            "User-Agent": WebFetch.defaultUA,
            "Accept": "text/html,*/*",
            "Referer": referer.absoluteString,
        ]
        let (status, data) = try await client.send(method: "GET", url: url, headers: headers, body: nil)
        if Self.blockedStatuses.contains(status) {
            throw HarvestHalt.blocked(status)
        }
        guard Self.successStatusRange.contains(status), let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw CrawlError.http(status)
        }
        return text
    }

    private func download(_ form: BizInfoAttachment, programID: String, referer: URL) async throws -> HarvestFile? {
        let url = BizInfoEndpoints.fileDownloadURL(atchFileId: form.atchFileId, fileSn: form.fileSn)
        let headers = [
            "User-Agent": WebFetch.defaultUA,
            "Accept": "*/*",
            "Referer": referer.absoluteString,
        ]
        let (status, data) = try await client.send(method: "GET", url: url, headers: headers, body: nil)
        if Self.blockedStatuses.contains(status) {
            throw HarvestHalt.blocked(status)
        }
        guard Self.successStatusRange.contains(status), !data.isEmpty, data.count <= Self.maxFileBytes else { return nil }
        let dir = hwpInbox.appendingPathComponent(programID, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = sanitize(form.fileName)
        let dest = dir.appendingPathComponent(safe)
        try data.write(to: dest, options: .atomic)
        return HarvestFile(fileName: safe, path: dest.path, bytes: data.count)
    }

    private func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "form.hwp" : cleaned
    }

    private func patchCatalog(programID: String, files: [HarvestFile]) {
        guard !files.isEmpty,
              let data = FileLoad.data(contentsOf: programsFile),
              var root = FileLoad.jsonObject(from: data) as? [String: Any],
              var rows = root["programs"] as? [[String: Any]] else { return }
        guard let idx = rows.firstIndex(where: { ($0["id"] as? String) == programID }) else { return }
        rows[idx]["requiredDocuments"] = files.map(\.fileName)
        rows[idx]["hwpTemplateHint"] = files.first?.fileName ?? ""
        root["programs"] = rows
        if let out = FileLoad.jsonData(root) {
            FileLoad.write(out, to: programsFile)
        }
    }
}

private enum HarvestHalt: Error {
    case blocked(Int)
}
