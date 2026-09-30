import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

extension LedgerModel {
    func refreshProtectionStatus() {
        guard let store else { return }
        Task.detached(priority: .background) {
            var problems = store.verify()
            if let checkpointProblems = store.verifyCheckpoint() {
                problems.append(contentsOf: checkpointProblems)
            }
            let checkpoint = store.latestCheckpoint(store.scan())
            let job = FileManager.default.fileExists(
                atPath: StateRootKit.path("Library/LaunchAgents/net.ranode.memo-citation-ledger.checkpoint.plist"))
            let (sync, versioning) = await Self.syncthingStatus()
            await MainActor.run {
                guard let model = LedgerModel.shared else { return }
                model.integrityProblemCount = problems.count
                model.lastCheckpoint = checkpoint
                model.checkpointJobLoaded = job
                model.remoteSyncPercent = sync
                model.remoteVersioningType = versioning
            }
        }
    }

    /// syncthing REST 로 복제·버저닝 상태 조회 (로컬 데몬, api key 는 config.xml).
    nonisolated private static func syncthingStatus() async -> (syncPercent: Int?, versioning: String?) {
        let configPath = StateRootKit.path("Library/Application Support/Syncthing/config.xml")
        guard let config = try? String(contentsOfFile: configPath, encoding: .utf8),
              let range = config.range(of: "<apikey>"),
              let end = config.range(of: "</apikey>") else { return (nil, nil) }
        let key = String(config[range.upperBound..<end.lowerBound])
        // async URLSession — 이전엔 DispatchSemaphore.wait 로 협조적 스레드풀 스레드를 device 수만큼
        // 최대 4초씩 누적 블록했다(Swift concurrency 금지 패턴). await 로 스레드를 양보한다.
        func get(_ path: String) async -> Data? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8384" + path)!)
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
            request.timeoutInterval = 3
            return try? await URLSession.shared.data(for: request).0
        }
        var versioning: String?
        var percent: Int?
        if let data = await get("/rest/config/folders/memo-ledger") {
            let json: [String: Any]?
            do {
                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            } catch {
                json = nil
            }
            if let json {
                versioning = (json["versioning"] as? [String: Any])?["type"] as? String
                if let devices = json["devices"] as? [[String: Any]] {
                    for device in devices {
                        guard let id = device["deviceID"] as? String, !id.isEmpty else { continue }
                        if let completion = await get("/rest/db/completion?folder=memo-ledger&device=\(id)") {
                            let cj: [String: Any]?
                            do {
                                cj = try JSONSerialization.jsonObject(with: completion) as? [String: Any]
                            } catch {
                                cj = nil
                            }
                            if let cj, let value = cj["completion"] as? Double, value < 100 || percent == nil {
                                percent = min(percent ?? 100, Int(value))
                            }
                        }
                    }
                }
            }
        }
        return (percent, versioning)
    }
}
