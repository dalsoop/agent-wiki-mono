import Foundation

extension VaultSession {
    /// 수리 파이프라인 일괄 쓰기. GUI·CLI 가 이 경로만 탄다.
    /// 첫 건 저장 뒤 sync 해서 URI 가 비면 나머지를 건드리지 않는다.
    public func fillLoginURIs(
        items: [VaultItem],
        rows: [VaultURIPipeline.Row],
        verifyFirst: Bool = true,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> VaultURIPipeline.FillResult {
        let chosen = rows.filter(\.fillable)
        var result = VaultURIPipeline.FillResult()
        var verified = !verifyFirst
        for (index, row) in chosen.enumerated() {
            defer { onProgress?(index + 1, chosen.count) }
            guard var item = items.first(where: { $0.id == row.itemID }) else { continue }
            item.loginURIs = VaultURIPipeline.normalizedURIList(row.proposedURI)
            item = VaultURIPipeline.applyAdoption(item)
            do {
                try await save(item)
                result.changed += 1
            } catch {
                result.failed.append("\(item.name): \(error.localizedDescription)")
                continue
            }
            guard !verified else { continue }
            let reloaded = try await syncItems().first { $0.id == item.id }
            guard let reloaded, !reloaded.needsLoginURI,
                  VaultURIPipeline.ledgerVersion(of: reloaded) >= VaultURIPipeline.schemaVersion else {
                result.changed = max(0, result.changed - 1)
                result.aborted = "중단: '\(item.name)' 저장 뒤 웹 주소 원장이 비었습니다. 나머지는 건드리지 않았습니다."
                result.failed.append(result.aborted ?? "")
                return result
            }
            verified = true
        }
        return result
    }

    /// 동기화 뒤 누락분. 확장 주소·사이트 태그·`vw.uri` 원장이 없는 로그인만 쓴다.
    public func adoptLoginURIs(items: [VaultItem]) async throws -> VaultURIPipeline.FillResult {
        try await fillLoginURIs(items: items, rows: VaultURIPipeline.expandScan(items: items).rows)
    }

    /// SSH·IP·로컬 로그인을 보안 메모로 옮긴 뒤 옛 로그인을 휴지통으로 보낸다.
    public func rehomeInfrastructureLogins(
        items: [VaultItem],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> VaultURIPipeline.FillResult {
        let rows = VaultURIPipeline.rehomeScan(items: items).rows
        var result = VaultURIPipeline.FillResult()
        for (index, row) in rows.enumerated() {
            defer { onProgress?(index + 1, rows.count) }
            guard let item = items.first(where: { $0.id == row.itemID }),
                  VaultURIPipeline.shouldRehomeToNote(item) else { continue }
            do {
                try await save(VaultURIPipeline.noteFromLogin(item))
                try await delete(id: item.id)
                result.changed += 1
            } catch {
                result.failed.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// 메모→로그인 역변환: rehome으로 만든 노트를 로그인으로 되돌린다.
    public func unhomeNotesToLogins(
        items: [VaultItem],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> VaultURIPipeline.FillResult {
        let rows = VaultURIPipeline.unhomeScan(items: items).rows
        var result = VaultURIPipeline.FillResult()
        for (index, row) in rows.enumerated() {
            defer { onProgress?(index + 1, rows.count) }
            guard let item = items.first(where: { $0.id == row.itemID }),
                  let login = VaultURIPipeline.loginFromNote(item) else { continue }
            do {
                try await save(login)
                try await delete(id: item.id)
                result.changed += 1
            } catch {
                result.failed.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// 망·운영·테넌트·소유자 스탬프. 로그인·메모만.
    public func adoptPlacement(items: [VaultItem]) async throws -> VaultURIPipeline.FillResult {
        let pending = VaultPlacement.scan(items: items)
        var result = VaultURIPipeline.FillResult()
        for item in pending {
            do {
                try await save(item)
                result.changed += 1
            } catch {
                result.failed.append("\(item.name): \(error.localizedDescription)")
            }
        }
        return result
    }
}
