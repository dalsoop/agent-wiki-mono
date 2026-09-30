import CommandKit
import Foundation
import StateRootKit
import SwiftUI

/// 스케줄러 — "언제 뭐가 도는가"의 단일 화면. launchd 루프의 트리거·다음 실행·최근 결과·토글.
struct SchedulerJob: Identifiable {
    let label: String
    let name: String
    let trigger: String          // 사람 읽는 트리거 설명 (달력 + 신호 조건)
    let plistPath: String
    let logPath: String
    var hour: Int?
    var minute: Int?

    var id: String { label }

    /// 다음 실행 예정 (달력 기반).
    var nextRun: Date? {
        guard let hour else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute ?? 0
        guard let today = Calendar.current.date(from: components) else { return nil }
        return today > Date() ? today : Calendar.current.date(byAdding: .day, value: 1, to: today)
    }
}

@MainActor
@Observable
final class SchedulerModel {
    var jobs: [SchedulerJob] = []
    var loadedLabels: Set<String> = []
    var lastLogs: [String: String] = [:]

    static let known: [SchedulerJob] = [
        SchedulerJob(label: "net.ranode.memo-vault.inbox-classifier",
                     name: "미정리 분류 (memo-vault)",
                     trigger: "매시 10분 — inbox 에 미정리가 있을 때만 기동",
                     plistPath: "net.ranode.memo-vault.inbox-classifier.plist",
                     logPath: StateRootKit.path(".memo-vault/logs/inbox-classifier.log"),
                     hour: nil, minute: 10),
        SchedulerJob(label: "net.ranode.memo-citation-ledger.checkpoint",
                     name: "체크포인트 (증발 감지 기준점)",
                     trigger: "매일 21:30 — 새 발행이 있을 때만 발행",
                     plistPath: "net.ranode.memo-citation-ledger.checkpoint.plist",
                     logPath: StateRootKit.path(".memo-citation-ledger/checkpoint.log"),
                     hour: 21, minute: 30),
        SchedulerJob(label: "net.ranode.memo-citation-ledger.librarian",
                     name: "야간 사서 (위키 층 종합·색인·역방향 갱신)",
                     trigger: "매일 03:30 — 최근 24h 새 발행이 있을 때만 기동 (sleep-time)",
                     plistPath: "net.ranode.memo-citation-ledger.librarian.plist",
                     logPath: StateRootKit.path(".memo-citation-ledger/librarian.log"),
                     hour: 3, minute: 30),
        SchedulerJob(label: "net.ranode.memo-citation-ledger.verifier",
                     name: "주간 재검증 (verifier — 신선도 낮은 근거 origin 재방문)",
                     trigger: "매주 월 04:30 — 재현/반박 발행으로 감쇠를 교정",
                     plistPath: "net.ranode.memo-citation-ledger.verifier.plist",
                     logPath: StateRootKit.path(".memo-citation-ledger/verifier.log"),
                     hour: 4, minute: 30),
        SchedulerJob(label: "net.ranode.memo-citation-ledger.backup",
                     name: "야간 백업 (restic 불변 스냅샷 → backup.json 저장소)",
                     trigger: "매일 22:30 — 보존 30d/12w/12m, 일요일 check 포함",
                     plistPath: "net.ranode.memo-citation-ledger.backup.plist",
                     logPath: StateRootKit.path(".memo-citation-ledger/backup.log"),
                     hour: 22, minute: 30),
    ]

    func refresh() {
        jobs = Self.known.filter {
            FileManager.default.fileExists(
                atPath: StateRootKit.path("Library/LaunchAgents/" + $0.plistPath))
        }
        Task.detached { [jobs] in
            let output = await Self.run(["launchctl", "list"])
            let loaded = Set(jobs.map(\.label).filter { output.contains($0) })
            var logs: [String: String] = [:]
            for job in jobs {
                if let text = try? String(contentsOfFile: job.logPath, encoding: .utf8) {
                    logs[job.label] = text.split(separator: "\n").last.map(String.init) ?? ""
                }
            }
            await MainActor.run {
                SchedulerModel.shared?.loadedLabels = loaded
                SchedulerModel.shared?.lastLogs = logs
            }
        }
        Self.shared = self
    }

    private static weak var shared: SchedulerModel?

    func toggle(_ job: SchedulerJob, enable: Bool) {
        let plist = StateRootKit.path("Library/LaunchAgents/" + job.plistPath)
        Task {
            _ = await Self.run(["launchctl", enable ? "load" : "unload", plist])
            refresh()
        }
    }

    func runNow(_ job: SchedulerJob) {
        Task {
            _ = await Self.run(["launchctl", "start", job.label])
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            refresh()
        }
    }

    nonisolated private static func run(_ arguments: [String]) async -> String {
        let runner = ProcessCommandRunner()
        let result = await runner.run("/usr/bin/env", arguments)
        return result.stdout
    }
}

struct SchedulerView: View {
    @State private var model = SchedulerModel()

    var body: some View {
        Form {
            ForEach(model.jobs) { job in
                Section(job.name) {
                    LabeledContent("트리거", value: job.trigger)
                    if let next = job.nextRun {
                        LabeledContent("다음 실행", value: next.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
                    } else {
                        LabeledContent("다음 실행", value: "매시 10분")
                    }
                    if let log = model.lastLogs[job.label], !log.isEmpty {
                        LabeledContent("마지막 결과") {
                            Text(log).font(.caption).lineLimit(2).frame(minWidth: 0).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Toggle("활성", isOn: Binding(
                            get: { model.loadedLabels.contains(job.label) },
                            set: { model.toggle(job, enable: $0) }))
                        Spacer()
                        Button("지금 실행") { model.runNow(job) }
                            .disabled(!model.loadedLabels.contains(job.label))
                    }
                }
            }
            if model.jobs.isEmpty {
                Text("등록된 루프 없음").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refresh() }
    }
}


