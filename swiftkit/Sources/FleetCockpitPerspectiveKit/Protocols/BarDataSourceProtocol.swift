import Foundation

/// 각 바 모드(App / Agent / Room)별 데이터 소스 공통 계약
public protocol BarDataSourceProtocol: Sendable {
    var mode: BarMode { get }

    /// 메모리에 사전 로드된 최신 아이템 즉시 반환 (0ms 호버/렌더링용)
    func currentItems() -> [UnifiedBarItem]

    /// 백그라운드 이벤트(OS 알림, FSEvents, 소켓) 변경 스트림
    var itemsStream: AsyncStream<[UnifiedBarItem]> { get }

    /// 활성화/비활성화 수명주기 (비활성 모드는 리소스 0% 유지)
    func activate() async
    func deactivate()
}
