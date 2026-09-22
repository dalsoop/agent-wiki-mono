import Foundation
import StatusIndicatorUIKit

/// CI 작업의 실행 상태.
public enum CIJobStatus: Sendable, Equatable, Hashable {
    case success
    case running
    case pending
    case failed
    case canceled
    case skipped
    case manual
    case other(String)

    public init(raw: String) {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "success", "successful", "passed", "completed":
            self = .success
        case "running", "in_progress":
            self = .running
        case "pending", "queued", "waiting_for_resource", "preparing", "waiting":
            self = .pending
        case "failed", "failure", "timed_out", "action_required":
            self = .failed
        case "canceled", "cancelled":
            self = .canceled
        case "skipped", "neutral":
            self = .skipped
        case "manual", "blocked":
            self = .manual
        default:
            self = .other(raw)
        }
    }

    public var rawValue: String {
        switch self {
        case .success: return "success"
        case .running: return "running"
        case .pending: return "pending"
        case .failed: return "failed"
        case .canceled: return "canceled"
        case .skipped: return "skipped"
        case .manual: return "manual"
        case .other(let val): return val
        }
    }

    public var tone: StatusIndicatorTone {
        switch self {
        case .success: return .success
        case .running: return .running
        case .pending, .manual: return .warning
        case .failed: return .error
        case .canceled, .skipped, .other: return .idle
        }
    }

    public var symbolName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .pending: return "clock.fill"
        case .failed: return "xmark.circle.fill"
        case .canceled: return "slash.circle.fill"
        case .skipped: return "forward.circle.fill"
        case .manual: return "play.circle.fill"
        case .other: return "questionmark.circle.fill"
        }
    }

    public var isRunning: Bool {
        self == .running
    }

    /// 심각도 순위 (worst status 계산용). failed > running > pending > canceled > skipped > success
    public var severityScore: Int {
        switch self {
        case .failed: return 5
        case .running: return 4
        case .pending: return 3
        case .canceled: return 2
        case .manual: return 1
        case .skipped: return 0
        case .other: return 0
        case .success: return -1
        }
    }
}

/// 단일 CI Job 모델 (GitLab CI / GitHub Actions 공용).
public struct CIJobItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let stage: String
    public let status: CIJobStatus
    public let duration: TimeInterval?
    public let queuedDuration: TimeInterval?
    public let startedAt: Date?
    public let finishedAt: Date?
    public let runner: String?
    public let webURL: String?

    public init(
        id: String,
        name: String,
        stage: String,
        status: CIJobStatus,
        duration: TimeInterval? = nil,
        queuedDuration: TimeInterval? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        runner: String? = nil,
        webURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.stage = stage
        self.status = status
        self.duration = duration
        self.queuedDuration = queuedDuration
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.runner = runner
        self.webURL = webURL
    }

    /// 사람이 읽기 쉬운 소요 시간 (예: "14m 16s", "42s").
    public var formattedDuration: String? {
        guard let duration, duration >= 0 else { return nil }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

/// 스테이지 단위로 묶인 CI 파이프라인 단계.
public struct CIPipelineStage: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let status: CIJobStatus
    public let jobs: [CIJobItem]

    public init(id: String, name: String, status: CIJobStatus, jobs: [CIJobItem]) {
        self.id = id
        self.name = name
        self.status = status
        self.jobs = jobs
    }

    /// 잡 목록을 스테이지별로 그룹화한다.
    public static func groupIntoStages(jobs: [CIJobItem]) -> [CIPipelineStage] {
        var stageOrder: [String] = []
        var jobsByStage: [String: [CIJobItem]] = [:]

        for job in jobs {
            let stageName = job.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : job.stage
            if jobsByStage[stageName] == nil {
                stageOrder.append(stageName)
                jobsByStage[stageName] = []
            }
            jobsByStage[stageName]?.append(job)
        }

        return stageOrder.map { stageName in
            let stageJobs = jobsByStage[stageName] ?? []
            let worstStatus = stageJobs.map(\.status).max(by: { $0.severityScore < $1.severityScore }) ?? .success
            return CIPipelineStage(
                id: stageName,
                name: stageName,
                status: worstStatus,
                jobs: stageJobs
            )
        }
    }
}
