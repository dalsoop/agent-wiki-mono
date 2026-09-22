import Foundation
import InteropKit
import CommandKit
import os

/// 방과 앱 간의 임차(Lease) 및 도구 관계 모델
public struct RoomLeaseEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let roomID: String
    public let cliName: String
    public let occupant: String
    public let occupantHandle: String
    public let roomTitle: String
    public let blueprintSlug: String
    public let workdir: String?
    public let isDeclared: Bool
    public let isLive: Bool

    public init(
        id: String,
        roomID: String,
        cliName: String,
        occupant: String,
        occupantHandle: String,
        roomTitle: String,
        blueprintSlug: String,
        workdir: String?,
        isDeclared: Bool,
        isLive: Bool
    ) {
        self.id = id
        self.roomID = roomID
        self.cliName = cliName
        self.occupant = occupant
        self.occupantHandle = occupantHandle
        self.roomTitle = roomTitle
        self.blueprintSlug = blueprintSlug
        self.workdir = workdir
        self.isDeclared = isDeclared
        self.isLive = isLive
    }

    public var shortOccupant: String {
        var name = occupant
        if name.hasPrefix("agent:") {
            name = String(name.dropFirst(6))
        }
        if let atIdx = name.firstIndex(of: "@") {
            name = String(name[..<atIdx])
        }
        return name.isEmpty ? occupantHandle : name
    }
}

/// 다차원 피벗 차원
public enum FleetPivotDimension: String, CaseIterable, Identifiable, Sendable, Codable {
    case byRoom
    case byApp
    case byAgent
    case byTenant

    public var id: String { rawValue }
}

/// 함대 다차원 피벗 매트릭스 스냅샷
public struct FleetMatrixSnapshot: Sendable, Equatable, Codable {
    public let rooms: [ActiveRoomEntry]
    public let appLeases: [String: [ActiveRoomEntry]] // CLI 이름 -> 방 목록
    public let agentRooms: [String: [ActiveRoomEntry]] // 에이전트 식별자 -> 방 목록
    public let tenantRooms: [String: [ActiveRoomEntry]] // 테넌트 ID -> 방 목록
    public let declaredTools: [String: [String]] // blueprintSlug -> [CLI 이름]

    public init(
        rooms: [ActiveRoomEntry] = [],
        appLeases: [String: [ActiveRoomEntry]] = [:],
        agentRooms: [String: [ActiveRoomEntry]] = [:],
        tenantRooms: [String: [ActiveRoomEntry]] = [:],
        declaredTools: [String: [String]] = [:]
    ) {
        self.rooms = rooms
        self.appLeases = appLeases
        self.agentRooms = agentRooms
        self.tenantRooms = tenantRooms
        self.declaredTools = declaredTools
    }

    public var totalActiveRooms: Int {
        rooms.count
    }

    public var totalActiveApps: Int {
        appLeases.keys.count
    }

    public var totalActiveAgents: Int {
        agentRooms.keys.count
    }

    /// 스냅샷의 데이터 정합성 및 피벗 무결성 불변식(Invariant)을 검증합니다.
    public var isValid: Bool {
        let roomIDs = Set(rooms.map(\.id))
        // 1. 방 ID 중복이 없어야 함
        guard roomIDs.count == rooms.count else { return false }

        // 2. 피벗 맵의 모든 방이 rooms에 등록된 참조 무결성을 유지해야 함
        for (_, mappedRooms) in appLeases {
            for room in mappedRooms {
                guard roomIDs.contains(room.id) else { return false }
            }
        }
        for (_, mappedRooms) in agentRooms {
            for room in mappedRooms {
                guard roomIDs.contains(room.id) else { return false }
            }
        }
        for (_, mappedRooms) in tenantRooms {
            for room in mappedRooms {
                guard roomIDs.contains(room.id) else { return false }
            }
        }

        return true
    }
}

/// 임차 및 피벗 매트릭스 데이터 소스
public enum RoomLeaseSource {
    /// 원자적 캐시 저장소 (Swift 6 Data Race 방지)
    internal static let cachedSnapshot = OSAllocatedUnfairLock<FleetMatrixSnapshot?>(initialState: nil)

    /// 현재 캐시된 매트릭스 스냅샷 조회 (원자적 조회)
    public static func cachedMatrix() -> FleetMatrixSnapshot {
        cachedSnapshot.withLock { $0 ?? FleetMatrixSnapshot() }
    }

    /// 원자적 캐시 설정 및 불변식 검증
    /// - Parameter snapshot: 갱신할 매트릭스 스냅샷
    /// - Returns: 불변식 검증을 통과하여 정상 갱신되었는지 여부
    @discardableResult
    public static func setCachedMatrix(_ snapshot: FleetMatrixSnapshot) -> Bool {
        guard snapshot.isValid else {
            return false
        }
        cachedSnapshot.withLock { $0 = snapshot }
        return true
    }

    /// 원자적 캐시 갱신 (In-place Mutation / Read-Modify-Write)
    /// - Parameter transform: 현재 캐시(또는 기본값)를 기반으로 새 스냅샷을 생성하는 클로저
    /// - Returns: 불변식을 만족하여 성공적으로 반영되었는지 여부
    @discardableResult
    public static func updateCachedMatrix(_ transform: @Sendable (FleetMatrixSnapshot) -> FleetMatrixSnapshot) -> Bool {
        cachedSnapshot.withLock { cache in
            let current = cache ?? FleetMatrixSnapshot()
            let newSnapshot = transform(current)
            guard newSnapshot.isValid else {
                return false
            }
            cache = newSnapshot
            return true
        }
    }

    /// 캐시 초기화
    public static func clearCachedMatrix() {
        cachedSnapshot.withLock { $0 = nil }
    }

    /// 캐시가 유효한지 확인 (존재 여부 및 불변식 검증)
    public static var hasValidCache: Bool {
        cachedSnapshot.withLock { cache in
            guard let cache else { return false }
            return cache.isValid
        }
    }

    public static func fetchSnapshot(
        workTodoCLI: String = HostPlatform.cliBinPath("agent-work-todo")
    ) -> FleetMatrixSnapshot {
        let rooms = RoomSource.listActiveRooms(cliPath: workTodoCLI)
        let blueprints = listBlueprints(cliPath: workTodoCLI)
        let snapshot = buildSnapshot(rooms: rooms, blueprints: blueprints)
        setCachedMatrix(snapshot)
        return snapshot
    }

    public static func leasedRooms(for appName: String, bundleId: String) -> [ActiveRoomEntry] {
        let snapshot = cachedMatrix()
        let lowerName = appName.lowercased().replacingOccurrences(of: " ", with: "-")
        let lastBundle = bundleId.split(separator: ".").last.map(String.init)?.lowercased() ?? ""

        if let rooms = snapshot.appLeases[lowerName], !rooms.isEmpty {
            return rooms
        }
        if let rooms = snapshot.appLeases[lastBundle], !rooms.isEmpty {
            return rooms
        }
        for (cli, rooms) in snapshot.appLeases {
            if lowerName.contains(cli) || cli.contains(lowerName) {
                return rooms
            }
        }
        return []
    }

    public static func listBlueprints(
        cliPath: String = HostPlatform.cliBinPath("agent-work-todo")
    ) -> [String: [String]] {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return [:]
        }
        let result = CommandKitSync.run(cliPath, ["room", "list"], timeout: 4)
        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
            return [:]
        }
        return decodeBlueprints(from: data)
    }

    public static func decodeBlueprints(from data: Data) -> [String: [String]] {
        let json: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            json = obj
        } catch {
            return [:]
        }
        guard let list = json["payload"] as? [[String: Any]] else {
            return [:]
        }
        var dict: [String: [String]] = [:]
        for item in list {
            guard let slug = item["slug"] as? String, !slug.isEmpty else { continue }
            let tools = item["toolbelt"] as? [String] ?? []
            dict[slug] = tools
        }
        return dict
    }

    public static func buildSnapshot(
        rooms: [ActiveRoomEntry],
        blueprints: [String: [String]]
    ) -> FleetMatrixSnapshot {
        // 중복 방 제거 (불변식 보장: 고유 ID)
        var seenIDs = Set<String>()
        var uniqueRooms: [ActiveRoomEntry] = []
        for room in rooms {
            if seenIDs.insert(room.id).inserted {
                uniqueRooms.append(room)
            }
        }

        var appMap: [String: [ActiveRoomEntry]] = [:]
        var agentMap: [String: [ActiveRoomEntry]] = [:]
        var tenantMap: [String: [ActiveRoomEntry]] = [:]

        for room in uniqueRooms {
            let agentKey = room.shortOccupant
            if !agentKey.isEmpty {
                agentMap[agentKey, default: []].append(room)
            }

            let tenantKey = room.tenantID.isEmpty ? "tenant:personal" : room.tenantID
            tenantMap[tenantKey, default: []].append(room)

            // 청사진에 선언된 도구(toolbelt) 추출
            let tools = blueprints[room.blueprintSlug] ?? []
            for tool in tools {
                appMap[tool, default: []].append(room)
            }
        }

        return FleetMatrixSnapshot(
            rooms: uniqueRooms,
            appLeases: appMap,
            agentRooms: agentMap,
            tenantRooms: tenantMap,
            declaredTools: blueprints
        )
    }
}
