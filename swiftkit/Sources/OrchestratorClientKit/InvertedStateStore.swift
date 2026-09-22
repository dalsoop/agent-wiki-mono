import Foundation
import os

/// UI에 불변으로 전달되는 전체 상태 스냅샷
public struct BridgeSnapshot: Sendable, Equatable {
    public let generatedAt: Date
    public let activeRooms: [BridgeRoomSummary]
    public let activeJobs: [BridgeJobSummary]
    public let attributions: [AttributedRoomJob]
    
    // 역색인 룩업 테이블
    public let roomJobsMap: [String: [BridgeJobSummary]]      // room.id -> [job]
    public let jobRoomMap: [String: BridgeRoomSummary]        // job.id -> room
    public let workdirRoomsMap: [String: [BridgeRoomSummary]] // canonical workdir -> [room]
    public let unassignedJobs: [BridgeJobSummary]
    public let unassignedRooms: [BridgeRoomSummary]

    public init(
        generatedAt: Date = Date(),
        activeRooms: [BridgeRoomSummary] = [],
        activeJobs: [BridgeJobSummary] = [],
        attributions: [AttributedRoomJob] = [],
        roomJobsMap: [String: [BridgeJobSummary]] = [:],
        jobRoomMap: [String: BridgeRoomSummary] = [:],
        workdirRoomsMap: [String: [BridgeRoomSummary]] = [:],
        unassignedJobs: [BridgeJobSummary] = [],
        unassignedRooms: [BridgeRoomSummary] = []
    ) {
        self.generatedAt = generatedAt
        self.activeRooms = activeRooms
        self.activeJobs = activeJobs
        self.attributions = attributions
        self.roomJobsMap = roomJobsMap
        self.jobRoomMap = jobRoomMap
        self.workdirRoomsMap = workdirRoomsMap
        self.unassignedJobs = unassignedJobs
        self.unassignedRooms = unassignedRooms
    }
}

/// 0ms 무지연 스레드-세이프 인메모리 역색인 저장소
public final class InvertedStateStore: Sendable {
    public static let shared = InvertedStateStore()

    private let stateLock = OSAllocatedUnfairLock<BridgeSnapshot>(initialState: BridgeSnapshot())
    private let streamContinuationLock = OSAllocatedUnfairLock<[UUID: AsyncStream<BridgeSnapshot>.Continuation]>(initialState: [:])

    public init() {}

    // MARK: - 0ms 동기 읽기 (UI 메인 스레드 전용)

    /// 현재 캐시된 최신 불변 스냅샷 즉시 반환 (I/O 0회, 비용 < 5μs)
    public func currentSnapshot() -> BridgeSnapshot {
        stateLock.withLock { $0 }
    }

    /// 특정 방에 할당된 AWO 잡 목록 즉시 조회
    public func jobs(forRoomID roomID: String) -> [BridgeJobSummary] {
        stateLock.withLock { $0.roomJobsMap[roomID] ?? [] }
    }

    /// 특정 잡이 귀속된 방 정보 즉시 조회
    public func room(forJobID jobID: String) -> BridgeRoomSummary? {
        stateLock.withLock { $0.jobRoomMap[jobID] }
    }

    /// 특정 작업 디렉터리를 점유하는 방 목록 즉시 조회
    public func rooms(forWorkdir workdir: String) -> [BridgeRoomSummary] {
        guard let canonical = AttributionEngine.canonicalPath(workdir) else { return [] }
        return stateLock.withLock { $0.workdirRoomsMap[canonical] ?? [] }
    }

    // MARK: - 반응형 스트림 구독

    /// 스냅샷 변경 시 실시간 브로드캐스트 스트림 생성
    public func snapshotStream() -> AsyncStream<BridgeSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            streamContinuationLock.withLock { dict in
                dict[id] = continuation
            }
            // 초기 스냅샷 즉시 방출
            continuation.yield(self.currentSnapshot())

            continuation.onTermination = { [weak self] _ in
                _ = self?.streamContinuationLock.withLock { dict in
                    dict.removeValue(forKey: id)
                }
            }
        }
    }

    // MARK: - 원자적 갱신 (엔진 내부 백그라운드 파이프라인 전용)

    public func commit(
        rooms: [BridgeRoomSummary],
        jobs: [BridgeJobSummary],
        blueprints: [String: [String]]
    ) {
        let (attributions, unassignedJobs, unassignedRooms) = AttributionEngine.attribute(
            rooms: rooms,
            jobs: jobs,
            blueprints: blueprints
        )

        var roomJobs: [String: [BridgeJobSummary]] = [:]
        var jobRoom: [String: BridgeRoomSummary] = [:]
        var workdirRooms: [String: [BridgeRoomSummary]] = [:]

        for attr in attributions {
            roomJobs[attr.room.id, default: []].append(attr.job)
            jobRoom[attr.job.id] = attr.room
        }

        for room in rooms {
            if let cDir = room.canonicalWorkdir {
                workdirRooms[cDir, default: []].append(room)
            }
        }

        let newSnapshot = BridgeSnapshot(
            generatedAt: Date(),
            activeRooms: rooms,
            activeJobs: jobs,
            attributions: attributions,
            roomJobsMap: roomJobs,
            jobRoomMap: jobRoom,
            workdirRoomsMap: workdirRooms,
            unassignedJobs: unassignedJobs,
            unassignedRooms: unassignedRooms
        )

        // 원자적 포인터 교체
        stateLock.withLock { $0 = newSnapshot }

        // 대기 중인 모든 비동기 구독자에게 알림
        let continuations = streamContinuationLock.withLock { Array($0.values) }
        for cont in continuations {
            cont.yield(newSnapshot)
        }
    }
}
