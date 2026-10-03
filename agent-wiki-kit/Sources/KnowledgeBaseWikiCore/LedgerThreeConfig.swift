import Foundation

// ledger 3 원장 계층 설정: 원장 키·전신·테넌트 대응표·기기 키.
// 근거: 결정 0007, docs/business-rules.md "원장 구성"·"전신".
// 설정 파일은 `~/.memo-citation-ledger/config.json`(BoundLedgerFile) 하나다. CLI 연결은 각 앱 CLI 가 한다.

/// 원장 키·기기 키 형식 `^[a-z][a-z0-9-]{1,40}$`.
public enum LedgerKeyFormat: Sendable {
    public static let pattern = "^[a-z][a-z0-9-]{1,40}$"

    public static func isValid(_ raw: String) -> Bool {
        let scalars = Array(raw.unicodeScalars)
        guard (2...41).contains(scalars.count), let first = scalars.first else { return false }
        guard ("a"..."z").contains(first) else { return false }
        return scalars.dropFirst().allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }
}

/// world 원장 키 규칙: 형식, 불변(다른 값으로 다시 쓰기 거부), world 사이 중복 금지.
public enum WorldLedgerKeyBinding: Sendable {
    public static func validate(
        worldName: String,
        key: String?,
        existing: BoundWorld?,
        catalog: WorldBindingCatalog
    ) -> String? {
        guard let key else { return nil }
        guard LedgerKeyFormat.isValid(key) else {
            return "invalid ledger key '\(key)': must match \(LedgerKeyFormat.pattern)"
        }
        if let old = existing?.key, old != key {
            return "ledger key is immutable: world '\(worldName)' has key '\(old)'"
        }
        if let owner = catalog.worlds.first(where: { $0.name != worldName && $0.key == key }) {
            return "ledger key '\(key)' is already used by world '\(owner.name)'"
        }
        return nil
    }
}

/// 전신 규칙: 하나, 사슬 아님, 등록된 world, 자기 자신·자기 상위 사슬 아님, 선언 후 다른 값으로 바꾸지 않음.
public enum WorldPredecessorBinding: Sendable {
    /// `catalog` 는 변경을 반영한 뒤의 목록이다.
    public static func validate(
        worldName: String,
        requested: String?,
        existing: String?,
        catalog: WorldBindingCatalog
    ) -> String? {
        if let requested, let existing, requested != existing {
            return "predecessor is immutable: world '\(worldName)' already declares '\(existing)'"
        }
        guard let predecessor = catalog.world(named: worldName)?.predecessor else { return nil }
        if predecessor == worldName {
            return "world '\(worldName)' cannot be its own predecessor"
        }
        guard let target = catalog.world(named: predecessor) else {
            return "unknown predecessor world: \(predecessor)"
        }
        if let further = target.predecessor {
            return "predecessor is not a chain: '\(predecessor)' already has predecessor '\(further)'"
        }
        if let successor = catalog.successorNames(of: worldName).first {
            return "predecessor is not a chain: '\(worldName)' is the predecessor of '\(successor)' and cannot declare its own"
        }
        if catalog.isAncestor(predecessor, of: worldName) {
            return "predecessor '\(predecessor)' is in the parent chain of '\(worldName)'"
        }
        return nil
    }
}

/// 테넌트 → 원장 판정 결과. 세션 적재가 쓴다.
public enum TenantLedgerResolution: Equatable, Sendable {
    case assigned(tenant: String, world: String)
    case unassigned(tenant: String)

    public var tenant: String {
        switch self {
        case .assigned(let tenant, _), .unassigned(let tenant): tenant
        }
    }

    public var worldName: String? {
        if case .assigned(_, let world) = self { return world }
        return nil
    }

    /// 대응된 world 이름, 표에 없으면 `unassigned`.
    public var label: String { worldName ?? TenantLedgerRouting.unassignedLabel }
}

public enum TenantLedgerRouting: Sendable {
    /// 테넌트 표시가 없으면 이 테넌트다.
    public static let defaultTenant = "personal"
    public static let unassignedLabel = "unassigned"

    public static func resolve(tenant: String?, tenantMap: [String: String]?) -> TenantLedgerResolution {
        let trimmed = tenant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let slug = trimmed.isEmpty ? defaultTenant : trimmed
        if let world = tenantMap?[slug], !world.isEmpty {
            return .assigned(tenant: slug, world: world)
        }
        return .unassigned(tenant: slug)
    }

    public static func resolve(tenant: String?, file: BoundLedgerFile) -> TenantLedgerResolution {
        resolve(tenant: tenant, tenantMap: file.tenantMap)
    }
}

/// ledger 3 최상위 설정 변경(world 추가는 `WorldMutation.adding` 의 key·predecessor).
public enum LedgerThreeConfigMutation: Sendable {
    /// 테넌트 slug → world. world 는 등록돼 있어야 한다.
    public static func settingTenantMap(
        in file: BoundLedgerFile,
        tenant: String,
        world: String
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        let slug = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            return .failure(WorldMutationFailure("tenant slug is empty"))
        }
        guard WorldBindingCatalog(worlds: file.effectiveWorlds).world(named: world) != nil else {
            return .failure(WorldMutationFailure("unknown world: \(world)"))
        }
        var next = file
        var map = next.tenantMap ?? [:]
        map[slug] = world
        next.tenantMap = map
        return .success(next)
    }

    /// 기기 키를 목록에 등록한다. 등록한 키는 지우거나 바꾸지 않는다.
    /// `asCurrent` 면 이 기기 키로도 지정한다. 이미 다른 이 기기 키가 있으면 거부한다.
    public static func registeringDevice(
        in file: BoundLedgerFile,
        key: String,
        asCurrent: Bool = true
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        guard LedgerKeyFormat.isValid(key) else {
            return .failure(WorldMutationFailure(
                "invalid device key '\(key)': must match \(LedgerKeyFormat.pattern)"))
        }
        if asCurrent, let current = file.currentDevice, current != key {
            return .failure(WorldMutationFailure(
                "device key is immutable: this device is already registered as '\(current)'"))
        }
        var next = file
        var devices = next.devices ?? []
        if !devices.contains(key) { devices.append(key) }
        next.devices = devices
        if asCurrent { next.currentDevice = key }
        return .success(next)
    }

    /// 드리밍 기기(하나)를 지정한다. 등록된 기기 키만.
    public static func settingDreamDevice(
        in file: BoundLedgerFile,
        key: String
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        guard (file.devices ?? []).contains(key) else {
            return .failure(WorldMutationFailure("device key '\(key)' is not registered"))
        }
        var next = file
        next.dreamDevice = key
        return .success(next)
    }
}
