import Foundation

public enum WorldWriteDenialReason: String, Codable, Equatable, Sendable {
    /// 다른 원장의 전신으로 지정된(보관된) world.
    case archivedPredecessor = "archived-predecessor"
    /// ledger 3 world 에 이 기기 키가 등록돼 있지 않음.
    case unregisteredDevice = "unregistered-device"
}

public struct WorldWriteDenial: Equatable, Sendable {
    public var world: String
    public var reason: WorldWriteDenialReason
    public var message: String

    public init(world: String, reason: WorldWriteDenialReason, message: String) {
        self.world = world
        self.reason = reason
        self.message = message
    }
}

/// 원장 쓰기 허용 판정 한 곳. 공포·개정·폐지·원상회복·체크포인트·승격 등 모든 쓰기 명령이 쓰기 전에 부른다.
/// - 보관된 world(다른 world 의 전신)는 모든 쓰기 거부.
/// - ledger 3 world(원장 키나 전신을 가진 world)는 이 기기 키가 등록돼 있어야 한다. ledger 2 world 는 기기 키를 보지 않는다.
/// 근거: 결정 0007, docs/standards.md "전신 쓰기 거부는 쓰기 게이트 한 곳".
public enum WorldWriteGate: Sendable {
    public static func denial(
        targetWorld: String,
        catalog: WorldBindingCatalog,
        registeredDevices: [String],
        currentDevice: String?
    ) -> WorldWriteDenial? {
        let successors = catalog.successorNames(of: targetWorld)
        if !successors.isEmpty {
            return WorldWriteDenial(
                world: targetWorld,
                reason: .archivedPredecessor,
                message: "world '\(targetWorld)' is archived (predecessor of '\(successors.joined(separator: "', '"))'): writes are refused")
        }
        guard catalog.isLedgerThree(targetWorld) else { return nil }
        guard let device = currentDevice, !device.isEmpty else {
            return WorldWriteDenial(
                world: targetWorld,
                reason: .unregisteredDevice,
                message: "this device has no registered device key: writes to '\(targetWorld)' are refused")
        }
        guard registeredDevices.contains(device) else {
            return WorldWriteDenial(
                world: targetWorld,
                reason: .unregisteredDevice,
                message: "device key '\(device)' is not registered: writes to '\(targetWorld)' are refused")
        }
        return nil
    }

    /// 설정 파일 하나로 판정. `catalog` 를 주지 않으면 파일의 world 목록을 쓴다.
    public static func denial(
        targetWorld: String,
        file: BoundLedgerFile,
        catalog: WorldBindingCatalog? = nil
    ) -> WorldWriteDenial? {
        denial(
            targetWorld: targetWorld,
            catalog: catalog ?? WorldBindingCatalog(worlds: file.effectiveWorlds),
            registeredDevices: file.devices ?? [],
            currentDevice: file.currentDevice)
    }
}
