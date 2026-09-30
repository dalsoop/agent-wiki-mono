import CommandKit
import KnowledgeBaseWikiCore
import SwiftUI
import SettingsUIKit

/// 백업 설정 — 4계층(정본/복제/스냅샷/restic 불변 백업) 상태와 수동 실행.
/// 원칙: 동기화 ≠ 백업 — syncthing 위에 restic 독립 저장소를 둔다 (3-2-1).
@MainActor @Observable
final class BackupStatus {
    struct Snapshot: Decodable {
        let short_id: String
        let time: String
    }

    var snapshots: [Snapshot] = []
    var lastLog: String = ""
    var running = false
    var message: String?

    nonisolated static let configPath = NSString(string: "~/.memo-citation-ledger/backup.json").expandingTildeInPath
    nonisolated static let logPath = NSString(string: "~/.memo-citation-ledger/backup.log").expandingTildeInPath

    struct Config: Codable {
        var repository: String
        var password: String
    }

    nonisolated static func loadConfig() -> Config {
        if let data = FileManager.default.contents(atPath: configPath) {
            do {
                return try JSONDecoder().decode(Config.self, from: data)
            } catch {
                // fall through to default
            }
        }
        // 저장소·비밀번호 기본값은 없다 — 옛 sftp 저장소 호스트는 50 대역과 함께 퇴역했다(2026-09-25).
        // 공개 저장소에 적힌 비밀번호는 비밀이 아니다(CLI 쪽 PR #5 와 같은 이유).
        return Config(repository: "", password: "")
    }

    var repository = ""
    var password = ""

    func loadEditable() {
        let config = Self.loadConfig()
        repository = config.repository
        password = config.password
    }

    func saveConfig() {
        let config = Config(repository: repository, password: password)
        if let data = try? JSONEncoder().encode(config) {
            do { try data.write(to: URL(fileURLWithPath: Self.configPath)) } catch { _ = error }
            message = "저장소 설정 저장됨"
            refresh()
        }
    }

    func refresh() {
        lastLog = (try? String(contentsOfFile: Self.logPath, encoding: .utf8))?
            .split(separator: "\n").suffix(3).joined(separator: "\n") ?? "(로그 없음)"
        // 저장소 미설정이면 restic 을 부르지 않는다 — 옛 기본 저장소로 넘어가지 않는다.
        guard !Self.loadConfig().repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            snapshots = []
            message = "restic 저장소 미설정(기본값 없음) — 저장소 칸에 sftp:<host>:<경로> 를 넣고 저장"
            return
        }
        Task.detached { [weak self] in
            let runner = ProcessCommandRunner()
            let config = Self.loadConfig()
            let result = await runner.run("/bin/bash", ["-lc",
                "RESTIC_PASSWORD=\(config.password) restic -r \(config.repository) snapshots --json --latest 10 2>/dev/null"])
            let data = Data(result.stdout.utf8)
            let rows: [Snapshot]
            do {
                rows = try JSONDecoder().decode([Snapshot].self, from: data)
            } catch {
                rows = []
            }
            await MainActor.run { [weak self] in self?.snapshots = rows.reversed() }
        }
    }

    func backupNow() {
        guard !running else { return }
        running = true
        message = "백업 실행 중…"
        Task.detached { [weak self] in
            let runner = ProcessCommandRunner()
            let result = await runner.run("/bin/bash", ["-lc", "\(LedgerModel.cliPath) backup"])
            let out = result.stdout + result.stderr
            await MainActor.run { [weak self] in
                self?.running = false
                self?.message = out.split(separator: "\n").suffix(2).joined(separator: " · ")
                self?.refresh()
            }
        }
    }
}

struct BackupSettingsView: View {
    @Bindable var model: LedgerModel
    @State private var status = BackupStatus()

    var body: some View {
        Form {
            Section {
                AboutSection()
            }

            Section("계층 (3-2-1 — 동기화 ≠ 백업)") {
                LabeledContent("① 정본", value: "~/gujo-wiki (md, append-only + sha 봉인)")
                LabeledContent("② 실시간 복제", value: "syncthing → 50서버 pod (양방향 30일 .stversions)")
                LabeledContent("③ 백업 (restic, 비암호 방침)", value: "매일 22:30 · 보존 30d/12w/12m · 일요일 check")
                LabeledContent("④ 증발 감지", value: "체크포인트 사슬 + verify (일일)")
            }
            Section("백업 설정 (Agent Wiki · ~/.memo-citation-ledger/backup.json)") {
                TextField("저장소 (restic -r)", text: $status.repository)
                    .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                HStack {
                    TextField("비밀번호 (공개 상수 — 비밀 아님, 결정 019f763b)", text: $status.password)
                        .textFieldStyle(.roundedBorder).font(.callout.monospaced())
                    Button("저장") { status.saveConfig() }
                        .disabled(status.repository.isEmpty || status.password.isEmpty)
                }
            }
            Section {
                HStack {
                    Text("최근 스냅샷 \(status.snapshots.count)개")
                    Spacer()
                    Button(status.running ? "실행 중…" : "지금 백업") { status.backupNow() }
                        .disabled(status.running)
                }
                ForEach(status.snapshots, id: \.short_id) { snapshot in
                    LabeledContent(snapshot.short_id, value: String(snapshot.time.prefix(19)).replacingOccurrences(of: "T", with: " "))
                        .font(.callout.monospaced())
                }
                if status.snapshots.isEmpty {
                    Text("스냅샷 조회 중… (restic 저장소 접근에 수 초)").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("restic 스냅샷") }
            Section("마지막 백업 로그") {
                Text(status.lastLog).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let message = status.message {
                    Text(message).font(.caption).foregroundStyle(.blue)
                }
            }
            Section {
                Text("""
                    복구(어느 호스트에서든): RESTIC_PASSWORD=memo-citation-ledger restic -r <저장소> restore latest --target <경로>. \
                    비밀번호는 공개 상수 — 백업 서버가 자가 소유라 암호화는 위협 모델 밖(결정 2026-07-19), 키 단일점 제거 우선.
                    """)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { status.loadEditable(); status.refresh() }
    }
}
