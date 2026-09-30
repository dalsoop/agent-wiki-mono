import Foundation
import InteropKit
import KnowledgeBaseWikiCore
import StateRootKit

extension LedgerModel {
    /// PATH 명령 연결은 배포 도구가 유일한 쓰기 주체다(위키 abb1f223). 화면은 안내만 한다.
    nonisolated static let cliPathGuidance = "PATH 연결은 배포(`app-build-manager ship <앱>`)가 한다."

    /// 에이전트를 앱에서 실행 — CLI `agent run` 위임 (엔진·하트비트·규약은 CLI 가 단일 구현).
    func runAgent(role: String, task: String) {
        // 실행 직전 게이트 — 앱과 버전이 어긋난 CLI 로는 절대 실행하지 않는다(옛 CLI 로 조용히
        // 도는 사고를 점(點)에서 차단). 미러에도 방송돼 있으므로 시스템 전체가 이미 안다.
        let installed = Self.installedCLIVersion()
        guard installed == LedgerVersion.current else {
            cliStaleVersion = installed.isEmpty ? "구버전(version 미지원)" : installed
            errorMessage = "CLI 버전 불일치 — 설치본 \(cliStaleVersion!), 앱 \(LedgerVersion.current). "
                + "옛 CLI 로 에이전트 실행을 막았습니다. \(Self.cliPathGuidance)"
            publishState()
            return
        }
        guard DualEntry.isSafeCLIExecutable(Self.cliPath) else {
            errorMessage = "안전 CLI 없음 — \(Self.cliPathGuidance)"
            publishState()
            return
        }
        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let process = Process()
        process.currentDirectoryURL = rootURL.map(RepositoryAgentRoleStore.repositoryRoot(forWorldRoot:))
        process.executableURL = URL(fileURLWithPath: Self.cliPath)
        process.arguments = ["agent", "run", role, task]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(StateRootKit.path(".local/bin")):/opt/homebrew/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        // 진행은 .runs/status.json 배너, 결과는 발행으로. 실패만 앱에 표면화.
        process.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            Task { @MainActor in
                LedgerModel.shared?.errorMessage = "에이전트 실행 실패: \(role) (코드 \(proc.terminationStatus))"
                LedgerModel.shared?.refresh()
            }
        }
        do { try process.run() } catch { errorMessage = "에이전트 기동 실패: \(error.localizedDescription)" }
    }

    /// 주기 재검 — refresh 마다 불리되 20초에 한 번. Process 없이 스탬프 우선.
    func maybeRecheckCLI() {
        let now = Date()
        if let last = session.lastCLICheck, now.timeIntervalSince(last) < 20 { return }
        session.lastCLICheck = now
        checkCLIVersion()
    }

    /// 설치된 CLI 버전 — Core `DualEntry` 정본 (스탬프 우선, 안전할 때만 Process).
    nonisolated static func installedCLIVersion() -> String {
        DualEntry.installedCLIVersion(expected: LedgerVersion.current, allowProcessProbe: true)
    }

    nonisolated static func isSafeCLIExecutable(_ path: String) -> Bool {
        DualEntry.isSafeCLIExecutable(path)
    }

    /// CLI 버전을 앱 Core 버전과 대조 — 어긋나면 배너·미러.
    func checkCLIVersion() {
        Task.detached {
            let installed = LedgerModel.installedCLIVersion()
            let stale = installed != LedgerVersion.current
                ? (installed.isEmpty ? "구버전/미설치" : installed) : nil
            await MainActor.run {
                guard let model = LedgerModel.shared, model.cliStaleVersion != stale else { return }
                model.cliStaleVersion = stale
                model.publishState()
            }
        }
    }
}
