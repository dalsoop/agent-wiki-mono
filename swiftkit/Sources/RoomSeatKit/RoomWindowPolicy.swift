import Foundation

/// 윈도우 격리 모드
public enum WindowIsolationMode: String, Codable, Sendable, Equatable {
    /// 0. 스트릭트 베이스라인 (기본값): 명시적 전역 모드가 아니면 Global Sticky 앱 + 활성 룸 창만 노출하고 타 창은 원자적 은닉 (화면 난장판 원천 차단)
    case strictBaseline
    
    /// 1. 가상 워크스페이스: 방 전환 시 소속 창만 Bring-to-Front (AXRaise), 타 방 창은 Hide (AeroSpace 방식)
    case virtualWorkspace
    
    /// 2. 전용 가상 데스크탑 (macOS Space): 각 방에 독립 데스크탑 매핑 (Switch만 수행)
    case dedicatedSpace
    
    /// 3. 공유 (격리 없음): 일반 호스트 모드
    case shared
}

/// 창의 공간 귀속 범위
public enum WindowScope: String, Codable, Sendable, Equatable {
    /// 특정 룸에 격리 귀속되는 창 (룸 비활성화 시 은닉)
    case roomSpecific
    /// 전역 상주 창 (Slack, 1Password, Finder 등 모든 룸에서 항시 노출 유지)
    case globalSticky
}

/// 앱 내부 및 연계 창의 계층 역할 (App Depth 계층화)
public enum WindowAppRole: String, Codable, Sendable, Equatable {
    /// D0: 메인 루트 창 (에디터 본체, 메인 브라우저 창 등)
    case primary
    /// D1: 직계 하위 작업 창 (서브 터미널, 보조 도구창, 파생 프리뷰)
    case childTool
    /// D2: 리프 인스펙터 창 (속성창, 디버그 패널, 상세 정보창)
    case inspector
    /// D2: 모달 다이얼로그 (경고창, 파일 열기 팝업)
    case modal
}

/// 방 비활성화 시 창 처리 정책
public enum WindowDeactivationAction: String, Codable, Sendable, Equatable {
    /// 창 숨김 (AXHidden)
    case hide
    /// Dock으로 최소화
    case minimize
    /// 현상태 유지
    case none
}

/// 방(Room)의 창 격리 및 디스플레이 정책 (순수 정책 계약)
public struct RoomWindowPolicy: Codable, Equatable, Sendable {
    /// 격리 모드 (기본: 스트릭트 베이스라인)
    public var mode: WindowIsolationMode
    
    /// 방 진입 시 소속 창 일괄 전면 활성화 여부
    public var autoFocusOnEnter: Bool
    
    /// 방 이탈(다른 방 진입) 시 기존 창 처리 방식
    public var deactivationAction: WindowDeactivationAction
    
    /// 허용된 최대 윈도우 개수 (스프롤 방지, 0이면 무제한)
    public var maxWindowCount: Int

    public init(
        mode: WindowIsolationMode = .strictBaseline,
        autoFocusOnEnter: Bool = true,
        deactivationAction: WindowDeactivationAction = .hide,
        maxWindowCount: Int = 8
    ) {
        self.mode = mode
        self.autoFocusOnEnter = autoFocusOnEnter
        self.deactivationAction = deactivationAction
        self.maxWindowCount = maxWindowCount
    }

    public static let `default` = RoomWindowPolicy()
}

/// 단일 창 귀속 식별자 (단일 PID 다중 윈도우 앱 충돌 방지 복합 키 및 계층 뎁스 지원)
public struct WindowIdentity: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UInt32 { cgWindowID }
    
    /// macOS 실시간 Window ID
    public let cgWindowID: UInt32
    
    /// 프로세스 PID
    public let pid: Int32
    
    /// 윈도우 생성 시점 Mach 타임스탬프 (윈도우 ID 재사용 감지용)
    public let birthMachTime: UInt64
    
    /// 소속 Room ID
    public let roomID: String
    
    /// 앱 번들 ID (예: "com.microsoft.VSCode", "net.ranode.agent-browser")
    public let bundleID: String
    
    /// 도구 기동 시 주입된 고유 스폰 토큰
    public let spawnToken: String?
    
    /// 창 타이틀
    public let title: String

    /// 창의 전역 상주 여부 (기본: 특정 룸에 귀속)
    public let scope: WindowScope

    /// 계층 뎁스 (0: Root/Primary, 1: Child Tool, 2: Leaf Inspector/Modal)
    public let depth: Int

    /// 부모 윈도우 ID (D1, D2 창의 부모 참조)
    public let parentWindowID: UInt32?

    /// 앱 내부 역할
    public let appRole: WindowAppRole

    /// 부모 축소/은닉 시 함께 연쇄 은닉(Cascade Collapse) 여부
    public let cascadeCollapse: Bool

    public init(
        cgWindowID: UInt32,
        pid: Int32,
        birthMachTime: UInt64 = 0,
        roomID: String,
        bundleID: String,
        spawnToken: String? = nil,
        title: String = "",
        scope: WindowScope = .roomSpecific,
        depth: Int = 0,
        parentWindowID: UInt32? = nil,
        appRole: WindowAppRole = .primary,
        cascadeCollapse: Bool = true
    ) {
        self.cgWindowID = cgWindowID
        self.pid = pid
        self.birthMachTime = birthMachTime
        self.roomID = roomID
        self.bundleID = bundleID
        self.spawnToken = spawnToken
        self.title = title
        self.scope = scope
        self.depth = depth
        self.parentWindowID = parentWindowID
        self.appRole = appRole
        self.cascadeCollapse = cascadeCollapse
    }
}

/// 윈도우 방향성 비순환 그래프 (Window Directed Acyclic Graph - App Depth 계층 관리)
public struct WindowDAG: Codable, Equatable, Sendable {
    public var windows: [WindowIdentity]

    public init(windows: [WindowIdentity] = []) {
        self.windows = windows
    }

    /// 계층 깊이별 그룹 (D0, D1, D2)
    public var depthGroups: [Int: [WindowIdentity]] {
        Dictionary(grouping: windows, by: { $0.depth })
    }

    /// 최대 계층 깊이
    public var maxDepth: Int {
        windows.map(\.depth).max() ?? 0
    }

    /// 위상 정렬 순서 (D0 -> D1 -> D2 순서로 활성화)
    public func topologicalOrder() -> [WindowIdentity] {
        windows.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            return lhs.cgWindowID < rhs.cgWindowID
        }
    }

    /// 역위상 정렬 순서 (D2 -> D1 -> D0 순서로 연쇄 은닉)
    public func reverseTopologicalOrder() -> [WindowIdentity] {
        windows.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth > rhs.depth
            }
            return lhs.cgWindowID > rhs.cgWindowID
        }
    }

    /// 특정 루트 윈도우의 직계 및 간접 자식 서브트리 창 목록 추출
    public func subtree(for rootWindowID: UInt32) -> [WindowIdentity] {
        var result: [WindowIdentity] = []
        var queue = [rootWindowID]
        var visited = Set<UInt32>([rootWindowID])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let children = windows.filter { $0.parentWindowID == current }
            for child in children {
                if !visited.contains(child.cgWindowID) {
                    visited.insert(child.cgWindowID)
                    queue.append(child.cgWindowID)
                    result.append(child)
                }
            }
        }
        return result
    }

    /// 단독 집중 모드(D0 Solo) 지원 여부 (서브트리 자식 창이 존재하는가)
    public func isSoloCapable(for rootWindowID: UInt32) -> Bool {
        !subtree(for: rootWindowID).isEmpty
    }
}

/// 룸 창 목록 스냅샷 원장 (windows.json)
public struct RoomWindowsSnapshot: Codable, Equatable, Sendable {
    public var roomID: String
    public var generatedAt: Date
    public var windows: [WindowIdentity]

    public init(
        roomID: String,
        generatedAt: Date = Date(),
        windows: [WindowIdentity] = []
    ) {
        self.roomID = roomID
        self.generatedAt = generatedAt
        self.windows = windows
    }

    /// 윈도우 DAG 객체 변환
    public var dag: WindowDAG {
        WindowDAG(windows: windows)
    }
}
