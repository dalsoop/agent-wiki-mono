import Foundation

extension LedgerStore {
    private func isRollbackExcluded(_ obj: LedgerObject, superseded: Set<String>, retracted: Set<String>) -> Bool {
        if superseded.contains(obj.id) { return true }
        if retracted.contains(obj.id) { return true }
        if obj.retracts != nil { return true }
        return false
    }

    /// 특정 에이전트(author)가 작성한 객체들을 찾아 일괄 롤백(철회 또는 이전 판 복원)하는 코어 비즈니스 로직.
    ///
    /// - Parameters:
    ///   - targetAuthor: 롤백 대상 작성자(에이전트).
    ///   - byAuthor: 롤백을 수행하는 작성자(운영자/감사관). 지정하지 않으면 targetAuthor(자진 철회) 또는 호출자.
    ///   - since: 지정 시점 이후(inclusive)에 발행된 객체만 필터링. nil이면 대상 작성자의 모든 객체 대상.
    ///   - quarantine: true일 경우 격리 태그 `quarantine`를 부착하고 본문에 격리 사유를 명시하여 철회.
    ///   - now: 롤백 수행 시각 (기본값 현재).
    /// - Returns: 새로 발행된 롤백 객체 목록 (빈 배열 시 대상 없음).
    @discardableResult
    public func rollback(
        author targetAuthor: String,
        byAuthor: String? = nil,
        since: Date? = nil,
        quarantine: Bool = false,
        now: Date = Date()
    ) throws -> [LedgerObject] {
        let objects = scan()
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })

        // 1. 이미 supersede되었거나 retract된 객체, 또는 본인이 철회 객체인 것은 제외
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))

        // 2. targetAuthor가 작성한 유효 객체 필터링 (since 조건 포함)
        let targets = objects.filter { obj in
            guard obj.author == targetAuthor else { return false }
            if let since, obj.published < since { return false }
            return !isRollbackExcluded(obj, superseded: superseded, retracted: retracted)
        }

        guard !targets.isEmpty else { return [] }

        let rollbackAuthor = byAuthor ?? targetAuthor
        let rollbackBatch = LedgerID.generate(now: now)
        var published: [LedgerObject] = []

        for target in targets {
            var tags: [String] = []
            if quarantine {
                tags.append("quarantine")
            }

            if let previousID = target.supersedes, let previous = byID[previousID] {
                // 이전 판(개정 전 버전)이 존재하면 이전 내용으로 재발행(supersedes: target.id)
                published.append(try publish(
                    author: rollbackAuthor,
                    title: previous.title,
                    body: previous.body,
                    now: now,
                    extras: LedgerPublishExtras(
                        cites: [.init(id: target.id, rel: "rolls-back")],
                        supersedes: target.id,
                        batch: rollbackBatch,
                        tags: tags
                    )
                ))
            } else {
                // 신규 생성물이었거나 이전 판이 없으면 철회(retracts: target.id)
                let body = quarantine
                    ? "quarantine rollback of author \(targetAuthor)"
                    : "rollback of author \(targetAuthor)"
                published.append(try publish(
                    author: rollbackAuthor,
                    title: target.title.map { "철회: \($0)" },
                    body: body,
                    now: now,
                    extras: LedgerPublishExtras(
                        retracts: target.id,
                        batch: rollbackBatch,
                        tags: tags
                    )
                ))
            }
        }

        return published
    }
}
