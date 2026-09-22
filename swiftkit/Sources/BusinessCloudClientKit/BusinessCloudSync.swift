import Foundation
import MoneyLedgerModels

/// `BusinessCloudSync.pull` 결과 요약. 각 엔티티별 수신 행 수 + 새 커서.
/// upserted 가 전부 0 이고 newCursor 가 nil 이면 서버에 신규 변경분이 없는 것이다.
public struct BusinessCloudPullSummary: Sendable, Equatable {
    public let upserted: [BusinessCloudEntity: Int]
    public let newCursor: String?
    /// 실제 변경분이 있었는지(하나라도 행을 받았는지).
    public var hadChanges: Bool { upserted.values.contains(where: { $0 > 0 }) }

    public init(upserted: [BusinessCloudEntity: Int], newCursor: String?) {
        self.upserted = upserted
        self.newCursor = newCursor
    }
}

/// business-api 에 유관한 동기화 엔진. pull 위주 — push 는 앱이 편집 시점에
/// `BusinessCloudClient.upsert*` 를 직접 호출하는 구조(pilot 단순화).
///
/// 동기화 모델:
/// - **Pull-only 본체**: `/sync/changes?since=<cursor>&entities=<csv>` 로 증분 변경분을 받아
///   `LocalSyncStore.apply*Upserts` 로 로컬에 붓는다.
/// - **커서**: 영속 lastSyncCursor(없으면 풀 싱크). 서버가 보낸 cursor(= max updated_at) 를
///   다음 since 로 영속화한다.
/// - **충돌**: pilot 은 서버가 SSOT. 서버 content_hash 멱등 + updated_at last-write-wins 에
///   의존하고, 클라이언트 충돌 해정 로직은 두지 않는다.
/// - **Delete 전파 한계**: pilot 은 upsert-only — 서버의 delete/tombstone 행을 로컬에 반영하지
///   않는다(`/sync/changes` 의 result.changes 도 upsert 행만 담는다는 가정). 삭제 동기화는
///   후속 단계에서 명시적으로 추가한다.
public actor BusinessCloudSync {
    private let client: BusinessCloudClient

    public init(client: BusinessCloudClient) {
        self.client = client
    }

    /// 서버에서 변경분을 당겨 로컬 store 에 붓고 새 커서를 영속화한다.
    /// entities 를 생략하면 7개 엔티티 전체.
    @discardableResult
    public func pull(
        into store: any LocalSyncStore,
        entities: [BusinessCloudEntity] = BusinessCloudEntity.allCases
    ) async throws -> BusinessCloudPullSummary {
        let cursor = await store.lastSyncCursor
        let response = try await client.syncChanges(since: cursor, entities: entities)
        var upserted: [BusinessCloudEntity: Int] = [:]
        let changes = response.changes

        if let rows = changes.accounts, !rows.isEmpty {
            try await store.applyAccountsUpserts(rows)
            upserted[.accounts] = rows.count
        }
        if let rows = changes.cards, !rows.isEmpty {
            try await store.applyCardsUpserts(rows)
            upserted[.cards] = rows.count
        }
        if let rows = changes.subscriptions, !rows.isEmpty {
            try await store.applySubscriptionsUpserts(rows)
            upserted[.subscriptions] = rows.count
        }
        if let rows = changes.transactions, !rows.isEmpty {
            try await store.applyTransactionsUpserts(rows)
            upserted[.transactions] = rows.count
        }
        if let rows = changes.businesses, !rows.isEmpty {
            try await store.applyBusinessesUpserts(rows)
            upserted[.businesses] = rows.count
        }
        if let rows = changes.import_batches, !rows.isEmpty {
            try await store.applyImportBatchesUpserts(rows)
            upserted[.importBatches] = rows.count
        }
        if let rows = changes.attachments, !rows.isEmpty {
            try await store.applyAttachmentsUpserts(rows)
            upserted[.attachments] = rows.count
        }

        // 커서는 변경분 유무와 무관하게 전진 — 서버가 준 cursor 를 다음 since 로 영속화.
        // 빈 cursor 는 서버가 아직 판정을 안 한 것이므로 덮어쓰지 않는다.
        if let newCursor = response.cursor, !newCursor.isEmpty {
            try await store.setLastSyncCursor(newCursor)
        }

        return BusinessCloudPullSummary(upserted: upserted, newCursor: response.cursor)
    }
}
