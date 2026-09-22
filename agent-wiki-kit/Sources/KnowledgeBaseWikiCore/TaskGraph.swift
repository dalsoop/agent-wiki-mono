import Foundation

/// 작업그래프 파생 — task/handoff/done 객체에서 상태·담당·완료를 뽑는다.
/// CLI(`task list`)와 GUI(워크보드)가 같은 로직을 공유한다(중복 금지).
/// 예약어를 안 늘리고 type + cite rel 로만 표현한다(SPEC 제3조):
///   task ← handoff(rel=delegates, 본문 "위임 → 대상") ← done(rel=completes)
public struct LedgerTaskGraph: Sendable {
    /// type==task 인 객체들(시간순).
    public let tasks: [LedgerObject]
    /// completes 로 닫힌 task id.
    public let completed: Set<String>
    /// task id → 마지막 위임 대상(handoff 본문에서 파싱).
    public let assignee: [String: String]
    /// task id → 마지막 상태 변화 시각(task 생성/위임/완료).
    public let updatedAt: [String: Date]
    public let orchestration: [String: RepositoryAgentTaskProjection]

    public init(objects: [LedgerObject], currentSourceCommit: String? = nil) {
        var assign: [String: String] = [:]
        var updates: [String: Date] = [:]
        let ordered = objects.sorted { ($0.published, $0.id) < ($1.published, $1.id) }
        let retractedIDs = Set(ordered.compactMap(\.retracts))
        let activeObjects = ordered.filter { !retractedIDs.contains($0.id) }
        for object in activeObjects {
            switch object.effectiveType {
            case "done":
                for cite in object.cites where cite.rel == "completes" {
                    updates[cite.id] = max(updates[cite.id] ?? .distantPast, object.published)
                }
            case "handoff":
                if let target = Self.handoffTarget(object.body) {
                    for cite in object.cites where cite.rel == "delegates" {
                        assign[cite.id] = target
                        updates[cite.id] = max(updates[cite.id] ?? .distantPast, object.published)
                    }
                }
            default: break
            }
        }
        self.tasks = activeObjects.filter { $0.effectiveType == "task" }
            .sorted { ($0.published, $0.id) < ($1.published, $1.id) }
        var projections: [String: RepositoryAgentTaskProjection] = [:]
        for task in tasks {
            updates[task.id] = max(updates[task.id] ?? .distantPast, task.published)
            projections[task.id] = RepositoryAgentOrchestration.projection(
                task: task, objects: activeObjects, currentSourceCommit: currentSourceCommit)
        }
        self.completed = Set(projections.compactMap { $0.value.state == .verified ? $0.key : nil })
        self.assignee = assign
        self.updatedAt = updates
        self.orchestration = projections
    }

    public func isDone(_ id: String) -> Bool { completed.contains(id) }
    public var open: [LedgerObject] { tasks.filter { !completed.contains($0.id) } }

    /// Versioned JSON contracts and GUI workboards consume the same derived task rows.
    public var items: [RepositoryTaskItem] {
        tasks.map { task in
            let status: RepositoryTaskItem.Status
            if completed.contains(task.id) {
                status = .completed
            } else if assignee[task.id] != nil {
                status = .delegated
            } else {
                status = .open
            }
            return RepositoryTaskItem(
                taskId: task.id,
                title: task.title ?? "(제목 없음)",
                status: status,
                assignee: assignee[task.id],
                author: task.author,
                createdAt: task.published,
                updatedAt: updatedAt[task.id] ?? task.published,
                orchestration: orchestration[task.id] ?? RepositoryAgentOrchestration.projection(
                    task: task, objects: []))
        }
    }

    /// handoff 본문 첫 줄 "위임 → 대상" 에서 대상을 뽑는다.
    static func handoffTarget(_ body: String) -> String? {
        guard let line = body.split(separator: "\n").first,
              let arrow = line.range(of: "→") else { return nil }
        let target = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        return target.isEmpty ? nil : target
    }
}
