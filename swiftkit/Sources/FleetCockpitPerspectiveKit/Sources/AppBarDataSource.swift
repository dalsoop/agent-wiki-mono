import Foundation
import os

/// macOS 실행 중인 일반 애플리케이션 및 핀 고정 앱을 제공하는 데이터 소스
public final class AppBarDataSource: BarDataSourceProtocol, Sendable {
    public let mode: BarMode = .appBar
    private let cachedItemsLock = OSAllocatedUnfairLock<[UnifiedBarItem]>(initialState: [])

    public init() {}

    public func currentItems() -> [UnifiedBarItem] {
        let items = cachedItemsLock.withLock { $0 }
        if items.isEmpty {
            return fallbackItems()
        }
        return items
    }

    public var itemsStream: AsyncStream<[UnifiedBarItem]> {
        AsyncStream { cont in
            cont.yield(self.currentItems())
        }
    }

    public func activate() async {
        // 기본 앱 목록 로드
        cachedItemsLock.withLock { $0 = fallbackItems() }
    }

    public func deactivate() {
        cachedItemsLock.withLock { $0 = [] }
    }

    public func update(with apps: [RunningApp]) {
        let items = apps.map { app in
            UnifiedBarItem(
                id: "app-\(app.bundleId)",
                title: app.name,
                subtitle: nil,
                icon: .appBundle(app.bundleId),
                statusDot: .none,
                badge: nil,
                subjobCount: 0,
                runningSubjobCount: 0,
                workdir: nil
            )
        }
        cachedItemsLock.withLock { $0 = items }
    }

    private func fallbackItems() -> [UnifiedBarItem] {
        return [
            UnifiedBarItem(
                id: "app-finder",
                title: "Finder",
                subtitle: nil,
                icon: .appBundle("com.apple.finder"),
                statusDot: .none,
                badge: nil,
                subjobCount: 0,
                runningSubjobCount: 0,
                workdir: nil
            )
        ]
    }
}
