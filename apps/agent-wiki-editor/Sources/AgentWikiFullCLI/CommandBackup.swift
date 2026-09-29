import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import CommandKit
import LocalizationKit

// restic 야간 백업 — objects·events·blobs(정본)만, state/(파생)는 제외.
struct BackupConfig: Codable {
    var repository: String
    var password: String

    static var path: String { StateRootKit.path(".memo-citation-ledger/backup.json") }

    static let defaultRepository = "sftp:pve:/var/backups/gujo-wiki-restic"

    /// 설정 파일(backup.json)이 우선이고, 없으면 기본 저장소 + 환경 변수 RESTIC_PASSWORD.
    /// 비밀번호 기본값은 두지 않는다. 공개 저장소에 적힌 값은 비밀이 아니기 때문이다.
    /// 어디서도 비밀번호를 못 얻으면 nil — 호출측이 실패로 끝낸다.
    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BackupConfig? {
        if let data = FileManager.default.contents(atPath: path) {
            do {
                let config = try JSONDecoder().decode(BackupConfig.self, from: data)
                if !config.password.isEmpty { return config }
            } catch {
                // fall through to environment
            }
        }
        guard let password = environment["RESTIC_PASSWORD"], !password.isEmpty else { return nil }
        return BackupConfig(repository: defaultRepository, password: password)
    }
}

func runBackup(arguments: [String]) {
    let wikiRoot = StateRootKit.path("gujo-wiki")
    guard let config = BackupConfig.load() else {
        fail("백업 비밀번호가 없습니다: \(BackupConfig.path) 의 password 또는 환경 변수 RESTIC_PASSWORD 를 설정하세요")
    }
    func restic(_ resticArguments: [String]) -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["RESTIC_PASSWORD"] = config.password
        environment["PATH"] = "\(HostPlatform.homebrewBin):" + (environment["PATH"] ?? "/usr/bin:/bin")
        let safeResult = SafeProcessRunner.run(
            "/usr/bin/env",
            ["restic", "-r", config.repository] + resticArguments,
            environment: environment
        )
        return safeResult.exitCode
    }
    // state/ 는 파생(index.db·graph.db·WAL) — md 정본·events·blobs 에서 언제든 재생성되므로
    // 불변 백업에서 제외해 스냅샷 팽창을 막는다. objects·events·blobs 는 정본이라 백업 유지.
    guard restic(["backup", wikiRoot, "--tag", "nightly",
                  "--exclude", wikiRoot + "/state"]) == 0 else { fail("restic backup 실패") }
    _ = restic(["forget", "--keep-daily", "30", "--keep-weekly", "12", "--keep-monthly", "12", "--prune"])
    if Calendar.current.component(.weekday, from: Date()) == 1 {  // 일요일
        _ = restic(["check"])
    }
    print(CLILocalization.format("CommandBackup.print", nowISO()))
}
