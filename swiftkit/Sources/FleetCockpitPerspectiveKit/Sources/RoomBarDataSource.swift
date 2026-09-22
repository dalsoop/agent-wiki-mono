import Foundation
import os

/// 활성 작업 방(Room)과 하위 AWO 파이프라인 잡을 통합 제공하는 데이터 소스
public final class RoomBarDataSource: BarDataSourceProtocol, Sendable {
    public let mode: BarMode = .roomBar
    private let store: InvertedStateStore
    private let contLock = OSAllocatedUnfairLock<AsyncStream<[UnifiedBarItem]>.Continuation?>(initialState: nil)

    private let tenantContLock = OSAllocatedUnfairLock<AsyncStream<[TenantRoomGroup]>.Continuation?>(initialState: nil)

    public init(store: InvertedStateStore = .shared) {
        self.store = store
        store.addListener { [weak self] in
            guard let self else { return }
            _ = self.contLock.withLock { $0?.yield(self.currentItems()) }
            _ = self.tenantContLock.withLock { $0?.yield(self.currentTenantGroups()) }
        }
    }

    public func currentItems() -> [UnifiedBarItem] {
        let rooms = store.currentRooms()
        let jobs = store.currentAwoJobs()
        return AttributionEngine.attribute(rooms: rooms, awoJobs: jobs)
    }

    /// 테넌트별 묶음 DTO 반환
    public func currentTenantGroups() -> [TenantRoomGroup] {
        store.currentTenantRoomGroups()
    }

    /// 테넌트 컨텍스트가 주입된 바 아이템 목록 반환 (각 방의 서브타이틀에 테넌트 명칭 표기)
    public func currentItemsWithTenantContext() -> [UnifiedBarItem] {
        let groups = currentTenantGroups()
        var items: [UnifiedBarItem] = []
        for group in groups {
            for item in group.barItems {
                let tenantLabel = group.tenant.name
                let newSubtitle: String
                if let sub = item.subtitle, !sub.isEmpty {
                    newSubtitle = "\(tenantLabel) • \(sub)"
                } else {
                    newSubtitle = tenantLabel
                }
                items.append(UnifiedBarItem(
                    id: item.id,
                    title: item.title,
                    subtitle: newSubtitle,
                    icon: item.icon,
                    statusDot: item.statusDot,
                    badge: item.badge,
                    subjobCount: item.subjobCount,
                    runningSubjobCount: item.runningSubjobCount,
                    workdir: item.workdir,
                    children: item.children,
                    model: item.model
                ))
            }
        }
        return items
    }

    public var itemsStream: AsyncStream<[UnifiedBarItem]> {
        AsyncStream { [weak self] cont in
            _ = self?.contLock.withLock { $0 = cont }
            cont.yield(self?.currentItems() ?? [])
        }
    }

    public var tenantGroupsStream: AsyncStream<[TenantRoomGroup]> {
        AsyncStream { [weak self] cont in
            _ = self?.tenantContLock.withLock { $0 = cont }
            cont.yield(self?.currentTenantGroups() ?? [])
        }
    }

    public func activate() async {
        store.startAutoRefresh(intervalSeconds: 2.0)
        _ = contLock.withLock { $0?.yield(currentItems()) }
        _ = tenantContLock.withLock { $0?.yield(currentTenantGroups()) }
    }

    public func deactivate() {
        store.stopAutoRefresh()
    }
}
