import Foundation
import CoreGraphics
import os

/// SWR 캐시 조회 결과
public enum CacheLookupResult<T: Sendable>: Sendable {
    /// TTL 이내의 신선한 캐시 (재검증 불필요)
    case fresh(T)
    /// TTL이 만료되었으나 이전 이미지가 존재 (화면 즉시 렌더링 가능 + 백그라운드 재검증 필요)
    case stale(T)
    /// 캐시에 존재하지 않음 (로딩 스켈레톤/플레이스홀더 표시 + 백그라운드 캡처 필요)
    case miss

    public var value: T? {
        switch self {
        case .fresh(let v), .stale(let v): return v
        case .miss: return nil
        }
    }

    public var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

/// 단일 캐시 엔트리 불변 구조체 (Sendable)
public struct ThumbnailEntry: Sendable {
    public let image: CGImage
    public let capturedAt: Date
    public var lastAccessedAt: Date
    public let captureDurationMs: Double
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(image: CGImage, capturedAt: Date = Date(), captureDurationMs: Double = 0) {
        self.image = image
        self.capturedAt = capturedAt
        self.lastAccessedAt = capturedAt
        self.captureDurationMs = captureDurationMs
        self.pixelWidth = image.width
        self.pixelHeight = image.height
    }
}

/// 캡처 요청 타깃 명세
public struct WindowCaptureTarget: Sendable, Hashable, Identifiable {
    public let id: String
    public let windowID: CGWindowID
    public let pid: pid_t
    public let title: String
    public let isForeground: Bool
    public let priority: Int // 0: Selected/Hovered, 1: Visible Neighbor, 2: Background

    public init(
        id: String,
        windowID: CGWindowID,
        pid: pid_t = 0,
        title: String = "",
        isForeground: Bool = false,
        priority: Int = 2
    ) {
        self.id = id
        self.windowID = windowID
        self.pid = pid
        self.title = title
        self.isForeground = isForeground
        self.priority = priority
    }
}

/// 캡처 완료 결과 아이템
public struct WindowCaptureResultItem: Sendable {
    public let id: String
    public let image: CGImage
    public let durationMs: Double

    public init(id: String, image: CGImage, durationMs: Double) {
        self.id = id
        self.image = image
        self.durationMs = durationMs
    }
}

/// 썸네일 캐시 추상화 프로토콜
public protocol WindowThumbnailCaching: Sendable {
    func lookup(id: String, isForeground: Bool, now: Date) -> CacheLookupResult<ThumbnailEntry>
    func claimRevalidationTargets(_ targets: [WindowCaptureTarget], now: Date) -> [WindowCaptureTarget]
    func storeBatch(items: [WindowCaptureResultItem], completedTargets: [WindowCaptureTarget])
    func invalidate(id: String)
    func flush()
    var count: Int { get }
}

/// Stale-While-Revalidate (SWR) 기반 고성능 썸네일 캐시 엔진.
/// GUI 렌더링 스레드에서 동기적 0ms 조회가 가능하도록 OSAllocatedUnfairLock으로 보호되며 True LRU를 지원합니다.
public final class WindowThumbnailCache: WindowThumbnailCaching, @unchecked Sendable {
    public static let shared = WindowThumbnailCache()

    private struct CacheState: Sendable {
        var entries: [String: ThumbnailEntry] = [:]
        var inflight: [String: Date] = [:]
    }

    private let state: OSAllocatedUnfairLock<CacheState>
    public let activeTTL: TimeInterval
    public let backgroundTTL: TimeInterval
    public let countLimit: Int
    public let inflightTimeout: TimeInterval

    public init(
        activeTTL: TimeInterval = 1.5,
        backgroundTTL: TimeInterval = 5.0,
        countLimit: Int = 32,
        inflightTimeout: TimeInterval = 5.0
    ) {
        self.activeTTL = activeTTL
        self.backgroundTTL = backgroundTTL
        self.countLimit = countLimit
        self.inflightTimeout = inflightTimeout
        self.state = OSAllocatedUnfairLock(initialState: CacheState())
    }

    /// 동기적 0ms 캐시 조회. Stale인 경우에도 직전 이미지를 반환하여 UI 깜빡임을 방지합니다.
    public func lookup(id: String, isForeground: Bool = false, now: Date = Date()) -> CacheLookupResult<ThumbnailEntry> {
        state.withLock { s in
            guard var entry = s.entries[id] else {
                return .miss
            }

            // True LRU 갱신: 접근 시간 갱신
            entry.lastAccessedAt = now
            s.entries[id] = entry

            let ttl = isForeground ? activeTTL : backgroundTTL
            let age = now.timeIntervalSince(entry.capturedAt)
            if age < ttl {
                return .fresh(entry)
            } else {
                return .stale(entry)
            }
        }
    }

    /// 타임아웃된 인플라이트를 정리하고, 현재 비행 중이지 않은 타겟들만 선점(claim)합니다.
    public func claimRevalidationTargets(_ targets: [WindowCaptureTarget], now: Date = Date()) -> [WindowCaptureTarget] {
        state.withLock { s in
            // 타임아웃된 비행 작업 정리 (SCK 지연 시 영구 블로킹 방지)
            s.inflight = s.inflight.filter { now.timeIntervalSince($0.value) < inflightTimeout }

            var claimed: [WindowCaptureTarget] = []
            for target in targets {
                if s.inflight[target.id] == nil {
                    s.inflight[target.id] = now
                    claimed.append(target)
                }
            }
            return claimed
        }
    }

    /// 배치 캡처 결과 저장 및 완료된 타깃의 inflight 상태 해제
    public func storeBatch(items: [WindowCaptureResultItem], completedTargets: [WindowCaptureTarget]) {
        state.withLock { s in
            for target in completedTargets {
                s.inflight.removeValue(forKey: target.id)
            }

            let now = Date()
            for item in items {
                s.entries[item.id] = ThumbnailEntry(
                    image: item.image,
                    capturedAt: now,
                    captureDurationMs: item.durationMs
                )
            }

            // True LRU: countLimit 초과 시 lastAccessedAt 기준 최하위 엔트리부터 축출
            if s.entries.count > countLimit {
                let sorted = s.entries.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
                let removeCount = s.entries.count - countLimit
                for (id, _) in sorted.prefix(removeCount) {
                    s.entries.removeValue(forKey: id)
                }
            }
        }
    }

    /// 특정 창 ID 무효화
    public func invalidate(id: String) {
        state.withLock { s in
            s.entries.removeValue(forKey: id)
            s.inflight.removeValue(forKey: id)
        }
    }

    /// 캐시 완전 초기화 (슬립, 화면 잠금, 메모리 압박 시 VRAM 0B 반환)
    public func flush() {
        state.withLock { s in
            s.entries.removeAll(keepingCapacity: false)
            s.inflight.removeAll(keepingCapacity: false)
        }
    }

    public var count: Int {
        state.withLock { $0.entries.count }
    }
}
