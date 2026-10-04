import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

extension LedgerModel {
    func refreshProtectionStatus() {
        guard let store, let rootURL else { return }
        let worldName = currentWorldName
        Task.detached(priority: .background) {
            // ledger 3 원장의 무결성은 ledger 3 감사(판단 대기는 위반 아님)가 정한다 — 화면 표시 모델 반영 때 채운다.
            // 옛 형식 검사(`LedgerStore.verify`)로 보면 모든 기록이 위반처럼 보인다.
            let isLedgerThree = worldName.map {
                LedgerBackgroundReader.lawTarget(worldName: $0, root: rootURL, config: LedgerConfig.load()).isLedgerThree
            } ?? false
            var problems: [LedgerStore.Violation] = []
            if !isLedgerThree {
                problems = store.verify()
                if let checkpointProblems = store.verifyCheckpoint() {
                    problems.append(contentsOf: checkpointProblems)
                }
            }
            let checkpoint = isLedgerThree ? nil : store.latestCheckpoint(store.scan())
            let job = FileManager.default.fileExists(
                atPath: StateRootKit.path("Library/LaunchAgents/net.ranode.memo-citation-ledger.checkpoint.plist"))
            let (sync, versioning) = await Self.syncthingStatus()
            await MainActor.run {
                guard let model = LedgerModel.shared else { return }
                if !isLedgerThree { model.integrityProblemCount = problems.count }
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
