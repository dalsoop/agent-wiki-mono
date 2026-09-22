import Foundation
import MoneyLedgerModels

/// 로컬 저장소 adapter 계약 — 앱(sqlite 원장 등)이 구현하고 `BusinessCloudSync.pull` 로 넘긴다.
///
/// 이 프로토콜이 이 킷의 **유일한 추상**이다. 동기화 로직 자체(커서·content_hash·충돌 판정)는
/// 이 킷 안에 business-api 계약으로 고정돼 있고, LocalSyncStore 는 단지 "받아들인 도메인
/// 행을 어디 어떻게 쓸지"의 adapter 지점만 연다. 행 디코딩은 이미 MoneyLedgerModels 타입으로
/// 끝난 상태로 넘어온다 — 이 킷이 저장소의 내부 인코딩을 알 필요 없게.
///
/// push(로컬→서버)는 파일럿에서 write-on-each-edit 경로로 — 앱이 편집 시점에
/// `BusinessCloudClient.upsert*` 를 직접 호출한다. 이 protocol 은 pull 쪽만 담당한다.
public protocol LocalSyncStore: Sendable {
    // MARK: - 엔티티별 upsert 적용(이미 디코딩된 MoneyLedgerModels 행)

    func applyAccountsUpserts(_ rows: [MoneyAccount]) async throws
    func applyCardsUpserts(_ rows: [MoneyCard]) async throws
    func applySubscriptionsUpserts(_ rows: [MoneySubscription]) async throws
    func applyTransactionsUpserts(_ rows: [MoneyTransaction]) async throws
    func applyBusinessesUpserts(_ rows: [BusinessProfile]) async throws
    func applyImportBatchesUpserts(_ rows: [ImportBatch]) async throws
    func applyAttachmentsUpserts(_ rows: [AttachmentRecord]) async throws

    // MARK: - 영속 커서(동기화 증분의 since 값)

    /// 마지막 동기화 커서(서버의 max updated_at ISO8601). 없으면 풀 싱크.
    var lastSyncCursor: String? { get async }

    /// 동기화 완료 후 새 커서를 영속화. 다음 pull 의 since 가 된다.
    func setLastSyncCursor(_ cursor: String) async throws
}
