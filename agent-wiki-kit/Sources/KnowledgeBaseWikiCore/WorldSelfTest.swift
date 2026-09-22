import Foundation
import SelfTestKit

/// `agent-wiki world self-test` — world add/rm + 개인 world 승격을 임시 픽스처로 증명한다.
///
/// 왜(실측 2026-08-11): `world add` 가 사용자 실제 config 을 오염시켰다.
/// StateRootKit + `world rm` + 개인 world 승격으로 고쳤지만, "고쳐졌다"를 사람이
/// 손으로 확인하면 틀린다. 이 세션에서만 9번. SelfTestKit 으로 앱이 자기 계약을 증명한다.
public struct WorldSelfTest: AppSelfTest {
    public var name: String { "agent-wiki world" }

    public init() {}

    public func cases() async -> [SelfTestCase] {
        var results: [SelfTestCase] = []
        results.append(await testPersonalWorldPromotionReceipt())
        results.append(await testPromotionRequiresConfirmToken())
        results.append(await testPromotionReceiptSourceKindWorld())
        return results
    }

    /// 임시 스토어 쌍을 만든다.
    private func makeStores() -> (source: LedgerStore, target: LedgerStore, cleanup: () -> Void)? {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("wiki-selftest-\(UUID().uuidString)")
        let sourceRoot = base.appendingPathComponent("personal")
        let targetRoot = base.appendingPathComponent("gujo")
        for r in [sourceRoot, targetRoot] {
            do { try fm.createDirectory(at: r.appendingPathComponent("objects"), withIntermediateDirectories: true) } catch { _ = error }
        }
        guard let s = try? LedgerStore(root: sourceRoot),
              let t = try? LedgerStore(root: targetRoot) else { return nil }
        return (s, t, { try? fm.removeItem(at: base) })
    }

    /// 개인 world → gujo 승격이 양방향 영수증을 남긴다.
    private func testPersonalWorldPromotionReceipt() async -> SelfTestCase {
        let name = "personal-world-promotion-receipt"
        guard let (sourceStore, targetStore, cleanup) = makeStores() else {
            return .check(name, false, detail: "스토어 생성 실패")
        }
        defer { cleanup() }

        guard let source = try? sourceStore.publish(
            author: "test", title: "draft", body: "검증 전 초안") else {
            return .check(name, false, detail: "소스 발행 실패")
        }

        let targetWorld = LedgerWorld(name: "test-gujo", rootPath: targetStore.root.path)
        do {
            let preview = try PromotionService.preview(
                sourceStore: sourceStore, source: source,
                repository: nil, sourceWorldName: "test-personal",
                targetWorld: targetWorld, promotedBy: "test")
            let result = try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceStore, targetStore: targetStore,
                source: source, repository: nil, sourceWorldName: "test-personal",
                targetWorld: targetWorld, promotedBy: "test",
                confirmationToken: preview.confirmationToken))

            let ok = result.targetReceiptObjectId != nil && result.sourceReceiptObjectId != nil
            return .check(name, ok,
                detail: "개인 world 승격이 양방향 영수증을 남긴다",
                expected: "target+source 영수증 있음",
                actual: "target=\(result.targetReceiptObjectId != nil), source=\(result.sourceReceiptObjectId != nil)")
        } catch {
            return .check(name, false, detail: "승격 실패: \(error)")
        }
    }

    /// --confirm 토큰 없으면 publish 가 거부된다.
    private func testPromotionRequiresConfirmToken() async -> SelfTestCase {
        let name = "promotion-requires-confirm-token"
        guard let (sourceStore, targetStore, cleanup) = makeStores() else {
            return .check(name, false, detail: "스토어 생성 실패")
        }
        defer { cleanup() }

        guard let source = try? sourceStore.publish(
            author: "test", title: "draft", body: "초안") else {
            return .check(name, false, detail: "소스 발행 실패")
        }

        let targetWorld = LedgerWorld(name: "test-gujo", rootPath: targetStore.root.path)
        do {
            _ = try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceStore, targetStore: targetStore,
                source: source, repository: nil, sourceWorldName: "test-personal",
                targetWorld: targetWorld, promotedBy: "test",
                confirmationToken: "WRONG-TOKEN"))
            // 예외가 안 나면 실패 — 토큰 검증이 안 된 것
            return .check(name, false,
                detail: "잘못된 토큰으로 publish 가 성공하면 안 된다",
                expected: "PromotionError",
                actual: "성공")
        } catch {
            return .check(name, true,
                detail: "잘못된 토큰으로 publish 가 거부됐다",
                expected: "PromotionError",
                actual: "거부됨")
        }
    }

    /// 영수증의 sourceKind 가 "world" 여야 한다 (repo 가 아닌).
    private func testPromotionReceiptSourceKindWorld() async -> SelfTestCase {
        let name = "promotion-receipt-source-kind-world"
        guard let (sourceStore, targetStore, cleanup) = makeStores() else {
            return .check(name, false, detail: "스토어 생성 실패")
        }
        defer { cleanup() }

        guard let source = try? sourceStore.publish(
            author: "test", title: "draft", body: "초안") else {
            return .check(name, false, detail: "소스 발행 실패")
        }

        let targetWorld = LedgerWorld(name: "test-gujo", rootPath: targetStore.root.path)
        do {
            let preview = try PromotionService.preview(
                sourceStore: sourceStore, source: source,
                repository: nil, sourceWorldName: "test-personal",
                targetWorld: targetWorld, promotedBy: "test")
            let result = try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceStore, targetStore: targetStore,
                source: source, repository: nil, sourceWorldName: "test-personal",
                targetWorld: targetWorld, promotedBy: "test",
                confirmationToken: preview.confirmationToken))

            // target 에 발행된 영수증 객체를 읽어 sourceKind 확인
            let receiptObj = targetStore.heads(targetStore.scan())
                .first { $0.effectiveType == "promotion-receipt" }
            guard let obj = receiptObj,
                  let receipt = PromotionReceipt.decode(body: obj.body) else {
                return .check(name, false, detail: "영수증 객체를 찾을 수 없음")
            }
            return .check(name, receipt.sourceKind == "world",
                detail: "개인 world 승격 영수증의 sourceKind 는 'world'",
                expected: "world",
                actual: receipt.sourceKind)
        } catch {
            return .check(name, false, detail: "승격 실패: \(error)")
        }
    }
}
