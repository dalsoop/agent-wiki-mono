import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let src = DispatchSource.makeTimerSource()
    src.schedule(deadline: .now() + seconds)
    src.setEventHandler { process.terminate() }
    src.resume()
    process.waitUntilExit()
    src.cancel()
}

// restic 야간 백업 — objects·events·blobs(정본)만, state/(파생)는 제외.
struct BackupConfig: Codable {
    var repository: String
    var password: String

    static var path: String { StateRootKit.path(".memo-citation-ledger/backup.json") }

    static func load() -> BackupConfig {
        if let data = FileManager.default.contents(atPath: path) {
            do {
                return try JSONDecoder().decode(BackupConfig.self, from: data)
            } catch {
                // fall through to default
            }
        }
        return BackupConfig(
            repository: "sftp:pve:/var/backups/gujo-wiki-restic",
            password: "memo-citation-ledger")
    }
}

public func runBackup(arguments: [String]) {
    let wikiRoot = StateRootKit.path("gujo-wiki")
    let config = BackupConfig.load()
    func restic(_ resticArguments: [String]) -> Int32 {
        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["restic", "-r", config.repository] + resticArguments
        var environment = ProcessInfo.processInfo.environment
        environment["RESTIC_PASSWORD"] = config.password
        environment["PATH"] = "\(HostPlatform.homebrewBin):" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        try? process.run()
        waitWithTimeout(process)
        return process.terminationStatus
    }
    // state/ 는 파생(index.db·graph.db·WAL) — md 정본·events·blobs 에서 언제든 재생성되므로
    // 불변 백업에서 제외해 스냅샷 팽창을 막는다. objects·events·blobs 는 정본이라 백업 유지.
    guard restic(["backup", wikiRoot, "--tag", "nightly",
                  "--exclude", wikiRoot + "/state"]) == 0 else { fail("restic backup 실패") }
    _ = restic(["forget", "--keep-daily", "30", "--keep-weekly", "12", "--keep-monthly", "12", "--prune"])
    if Calendar.current.component(.weekday, from: Date()) == 1 {  // 일요일
        _ = restic(["check"])
    }
    print("\(nowISO()) backup 완료") // allow:debug
}
