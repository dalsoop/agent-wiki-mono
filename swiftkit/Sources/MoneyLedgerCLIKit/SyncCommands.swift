import CommandKit
import Foundation
import InteropKit
import MoneyLedgerKit

enum SyncCommands {
    static func run(
        context: LedgerContext,
        sub: [String],
        scanner: ArgScanner,
        json: Bool,
        output: CLIOutput
    ) async throws {
        let action = sub.first ?? "status"
        let remoteHost = scanner.value("remote") ?? "next-mac"
        let dryRun = scanner.has("dry-run")

        switch action {
        case "status":
            try await status(context: context, remoteHost: remoteHost, json: json, output: output)
        case "pull":
            try await pull(context: context, remoteHost: remoteHost, dryRun: dryRun, json: json, output: output)
        case "push":
            if scanner.has("help") || scanner.has("h") {
                output.out("Usage: sync push [--remote <host>] [--dry-run] [--json]")
                return
            }
            try await push(context: context, remoteHost: remoteHost, dryRun: dryRun, json: json, output: output)
        case "merge":
            if scanner.has("help") || scanner.has("h") {
                output.out("Usage: sync merge [--remote <host>] [--dry-run] [--json]")
                return
            }
            try await merge(context: context, remoteHost: remoteHost, dryRun: dryRun, json: json, output: output)
        default:
            throw UsageError("unknown sync action: \(action) (expected: status, pull, push, merge)")
        }
    }

    /// 원격 기기의 동적 원장 SQLite 경로 조회
    private static func resolveRemotePath(context: LedgerContext, remoteHost: String) -> String {
        let cmd = "echo \"$HOME/Library/Application Support/\(context.scope.appName)/ledger.sqlite\""
        let res = CommandKitSync.run("/usr/bin/ssh", [remoteHost, cmd], timeout: 5)
        if res.exitCode == 0, !res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(NSHomeDirectory())/Library/Application Support/\(context.scope.appName)/ledger.sqlite"
    }

    /// WAL 체크포인트를 안전하게 강제하여 메모리/저널 데이터를 본체 sqlite에 병합
    private static func checkpointLocalWAL(path: String) {
        _ = CommandKitSync.run("/usr/bin/sqlite3", [path, "PRAGMA wal_checkpoint(TRUNCATE);"], timeout: 5)
    }

    private static func checkpointRemoteWAL(remoteHost: String, remotePath: String) {
        _ = CommandKitSync.run("/usr/bin/ssh", [remoteHost, "sqlite3 \"\(remotePath)\" \"PRAGMA wal_checkpoint(TRUNCATE);\""], timeout: 5)
    }

    private struct LedgerStats: Sendable {
        var accounts: Int = 0
        var cards: Int = 0
        var subscriptions: Int = 0
        var budgets: Int = 0
        var transactions: Int = 0
        var size: Int64 = 0
        var latestTx: String? = nil
    }

    private static func localStats(context: LedgerContext) async throws -> LedgerStats {
        let localPath = context.databaseURL.path
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0

        guard fm.fileExists(atPath: localPath) else {
            return LedgerStats()
        }

        let store = try LedgerStore(context: context)
        let accounts = (try? await store.accounts(includeArchived: true).count) ?? 0
        let cards = (try? await store.cards(includeArchived: true).count) ?? 0
        let subs = (try? await store.subscriptions(includeArchived: true).count) ?? 0
        let budgets = (try? await store.budgets(month: nil).count) ?? 0
        let txs = (try? await store.transactions(TransactionQuery())) ?? []
        let latestDate = txs.max(by: { $0.date < $1.date })?.date
        return LedgerStats(
            accounts: accounts,
            cards: cards,
            subscriptions: subs,
            budgets: budgets,
            transactions: txs.count,
            size: size,
            latestTx: latestDate
        )
    }

    private static func remoteStats(context: LedgerContext, remoteHost: String) -> LedgerStats {
        let remotePath = resolveRemotePath(context: context, remoteHost: remoteHost)
        checkpointRemoteWAL(remoteHost: remoteHost, remotePath: remotePath)
        let remoteCmd = "sqlite3 \"\(remotePath)\" \"SELECT count(*) FROM accounts; SELECT count(*) FROM cards; SELECT count(*) FROM subscriptions; SELECT (CASE WHEN EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'budgets') THEN (SELECT count(*) FROM budgets) ELSE 0 END); SELECT count(*) FROM transactions; SELECT max(date) FROM transactions;\""
        let res = CommandKitSync.run("/usr/bin/ssh", [remoteHost, remoteCmd], timeout: 10)
        guard res.exitCode == 0 else {
            return LedgerStats(accounts: -1, cards: -1, subscriptions: -1, budgets: -1, transactions: -1, size: -1, latestTx: nil)
        }
        let lines = res.stdout.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        let accCount = lines.indices.contains(0) ? (Int(lines[0]) ?? 0) : 0
        let cardCount = lines.indices.contains(1) ? (Int(lines[1]) ?? 0) : 0
        let subCount = lines.indices.contains(2) ? (Int(lines[2]) ?? 0) : 0
        let budgetCount = lines.indices.contains(3) ? (Int(lines[3]) ?? 0) : 0
        let txCount = lines.indices.contains(4) ? (Int(lines[4]) ?? 0) : 0
        let latest = lines.indices.contains(5) && !lines[5].isEmpty ? lines[5] : nil
        return LedgerStats(
            accounts: accCount,
            cards: cardCount,
            subscriptions: subCount,
            budgets: budgetCount,
            transactions: txCount,
            size: 0,
            latestTx: latest
        )
    }

    private static func checkInSync(local: LedgerStats, remote: LedgerStats) -> Bool {
        local.transactions == remote.transactions &&
        local.accounts == remote.accounts &&
        local.cards == remote.cards &&
        local.subscriptions == remote.subscriptions &&
        local.budgets == remote.budgets
    }

    private static func status(
        context: LedgerContext,
        remoteHost: String,
        json: Bool,
        output: CLIOutput
    ) async throws {
        checkpointLocalWAL(path: context.databaseURL.path)
        let local = try await localStats(context: context)
        let remote = remoteStats(context: context, remoteHost: remoteHost)
        let inSync = checkInSync(local: local, remote: remote)

        if json {
            renderStatusJSON(context: context, remoteHost: remoteHost, local: local, remote: remote, inSync: inSync, output: output)
        } else {
            renderStatusText(context: context, remoteHost: remoteHost, local: local, remote: remote, inSync: inSync, output: output)
        }
    }

    private static func renderStatusJSON(
        context: LedgerContext,
        remoteHost: String,
        local: LedgerStats,
        remote: LedgerStats,
        inSync: Bool,
        output: CLIOutput
    ) {
        output.okJSON([
            "local": [
                "path": context.databaseURL.path,
                "accounts": local.accounts,
                "cards": local.cards,
                "subscriptions": local.subscriptions,
                "budgets": local.budgets,
                "transactions": local.transactions,
                "latestTx": local.latestTx ?? "",
                "sizeBytes": local.size
            ],
            "remote": [
                "host": remoteHost,
                "connected": remote.accounts >= 0,
                "accounts": max(0, remote.accounts),
                "cards": max(0, remote.cards),
                "subscriptions": max(0, remote.subscriptions),
                "budgets": max(0, remote.budgets),
                "transactions": max(0, remote.transactions),
                "latestTx": remote.latestTx ?? ""
            ],
            "inSync": inSync
        ])
    }

    private static func renderStatusText(
        context: LedgerContext,
        remoteHost: String,
        local: LedgerStats,
        remote: LedgerStats,
        inSync: Bool,
        output: CLIOutput
    ) {
        output.out("=== 원장 동기화 상태 (SSOT Ledger Status) ===")
        output.out("로컬 (내 MacBook):")
        output.out("  - 경로: \(context.databaseURL.path)")
        output.out("  - 계좌: \(local.accounts)개 | 카드: \(local.cards)개 | 구독: \(local.subscriptions)개 | 예산: \(local.budgets)개 | 거래: \(local.transactions)건 | 최신 거래: \(local.latestTx ?? "없음")")
        output.out("원격 (\(remoteHost)):")
        guard remote.accounts >= 0 else {
            output.out("  - 연결 실패 또는 원장 없음")
            return
        }
        output.out("  - 연결: 정상")
        output.out("  - 계좌: \(remote.accounts)개 | 카드: \(remote.cards)개 | 구독: \(remote.subscriptions)개 | 예산: \(remote.budgets)개 | 거래: \(remote.transactions)건 | 최신 거래: \(remote.latestTx ?? "없음")")
        let verdict = inSync ? "\n결과: 양쪽 기기의 원장이 완벽하게 일치합니다 (In Sync)." : "\n결과: 불일치 발견! 안전한 양방향 병합 권장 (sync merge)."
        output.out(verdict)
    }

    private static func pull(
        context: LedgerContext,
        remoteHost: String,
        dryRun: Bool,
        json: Bool,
        output: CLIOutput
    ) async throws {
        let localPath = context.databaseURL.path
        let remotePath = resolveRemotePath(context: context, remoteHost: remoteHost)

        guard !dryRun else {
            output.out("[dry-run] scp \(remoteHost):\(remotePath) -> \(localPath)")
            return
        }

        checkpointRemoteWAL(remoteHost: remoteHost, remotePath: remotePath)
        createLocalBackup(localPath: localPath, output: output)

        let res = CommandKitSync.run("/usr/bin/scp", ["\(remoteHost):\(remotePath)", localPath], timeout: 30)
        guard res.exitCode == 0 else {
            throw UsageError("원격 원장 가져오기(pull) 실패: \(res.stderr)")
        }

        let newLocal = try await localStats(context: context)
        renderPullResult(json: json, newLocal: newLocal, remoteHost: remoteHost, output: output)
    }

    private static func createLocalBackup(localPath: String, output: CLIOutput) {
        guard FileManager.default.fileExists(atPath: localPath) else { return }
        let backupPath = "\(localPath).bak.\(Int(Date().timeIntervalSince1970))"
        do {
            try FileManager.default.copyItem(atPath: localPath, toPath: backupPath)
        } catch {
            output.err("로컬 원장 백업 생성 실패: \(error)")
        }
    }

    private static func renderPullResult(json: Bool, newLocal: LedgerStats, remoteHost: String, output: CLIOutput) {
        if json {
            output.okJSON(["status": "pulled", "transactions": newLocal.transactions, "accounts": newLocal.accounts])
        } else {
            output.out("✓ 원격(\(remoteHost)) 원장을 로컬로 안전하게 가져왔습니다 (계좌 \(newLocal.accounts)개, 거래 \(newLocal.transactions)건).")
        }
    }

    private static func push(
        context: LedgerContext,
        remoteHost: String,
        dryRun: Bool,
        json: Bool,
        output: CLIOutput
    ) async throws {
        let localPath = context.databaseURL.path
        let remotePath = resolveRemotePath(context: context, remoteHost: remoteHost)

        guard !dryRun else {
            output.out("[dry-run] scp \(localPath) -> \(remoteHost):\(remotePath)")
            return
        }

        checkpointLocalWAL(path: localPath)

        let res = CommandKitSync.run("/usr/bin/scp", [localPath, "\(remoteHost):\(remotePath)"], timeout: 30)
        guard res.exitCode == 0 else {
            throw UsageError("원격 원장 보내기(push) 실패: \(res.stderr)")
        }

        if json {
            output.okJSON(["status": "pushed", "remoteHost": remoteHost])
        } else {
            output.out("✓ 로컬 원장을 원격(\(remoteHost))으로 성공적으로 전송했습니다.")
        }
    }

    /// 양방향 멱등 병합 (Two-Way Merge): 한쪽의 데이터를 일방적으로 덮어씌워 유실시키지 않고, 양쪽 거래/계좌를 합침
    private static func merge(
        context: LedgerContext,
        remoteHost: String,
        dryRun: Bool,
        json: Bool,
        output: CLIOutput
    ) async throws {
        let localPath = context.databaseURL.path
        let remotePath = resolveRemotePath(context: context, remoteHost: remoteHost)

        checkpointLocalWAL(path: localPath)
        checkpointRemoteWAL(remoteHost: remoteHost, remotePath: remotePath)

        let report = try await executeRemoteMerge(context: context, remoteHost: remoteHost, remotePath: remotePath, dryRun: dryRun)

        checkpointLocalWAL(path: localPath)
        try pushMergedStateIfNeeded(dryRun: dryRun, localPath: localPath, remoteHost: remoteHost, remotePath: remotePath)

        if json {
            renderMergeJSON(report: report, dryRun: dryRun, output: output)
        } else {
            renderMergeText(report: report, dryRun: dryRun, remoteHost: remoteHost, output: output)
        }
    }

    private static func executeRemoteMerge(
        context: LedgerContext,
        remoteHost: String,
        remotePath: String,
        dryRun: Bool
    ) async throws -> SyncMergeReport {
        let tmpRemoteDB = NSTemporaryDirectory().appending("remote_ledger_\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(atPath: tmpRemoteDB) }

        let scpRes = CommandKitSync.run("/usr/bin/scp", ["\(remoteHost):\(remotePath)", tmpRemoteDB], timeout: 30)
        guard scpRes.exitCode == 0 else {
            throw UsageError("원격 스냅샷 다운로드 실패: \(scpRes.stderr)")
        }

        let localStore = try LedgerStore(context: context)
        let remoteContext = LedgerContext(scope: context.scope, databaseURL: URL(fileURLWithPath: tmpRemoteDB))
        let remoteStore = try LedgerStore(context: remoteContext)

        return try await LedgerSyncEngine.merge(from: remoteStore, into: localStore, dryRun: dryRun)
    }

    private static func pushMergedStateIfNeeded(
        dryRun: Bool,
        localPath: String,
        remoteHost: String,
        remotePath: String
    ) throws {
        guard !dryRun else { return }
        let pushRes = CommandKitSync.run("/usr/bin/scp", [localPath, "\(remoteHost):\(remotePath)"], timeout: 30)
        guard pushRes.exitCode == 0 else {
            throw UsageError("병합된 원장 푸시 실패: \(pushRes.stderr)")
        }
        checkpointRemoteWAL(remoteHost: remoteHost, remotePath: remotePath)
    }
}
