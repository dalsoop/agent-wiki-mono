import Foundation
import SwiftUI

/// 동심원 방사형 그래프의 티어 (거리 구간)
public enum RadialTier: Int, Sendable, Codable, CaseIterable, Comparable {
    case core = 0      // 0.00 ~ 0.25 (중심 밀접)
    case near = 1      // 0.25 ~ 0.50 (근거리)
    case mid = 2       // 0.50 ~ 0.75 (중거리)
    case outer = 3     // 0.75 ~ 1.00 (외곽 경계)

    public var normalizedRange: ClosedRange<Double> {
        switch self {
        case .core:  return 0.0 ... 0.25
        case .near:  return 0.25 ... 0.50
        case .mid:   return 0.50 ... 0.75
        case .outer: return 0.75 ... 1.00
        }
    }

    public static func tier(for distance: Double) -> RadialTier {
        let clamped = min(max(distance, 0.0), 1.0)
        switch clamped {
        case ...0.25: return .core
        case ...0.50: return .near
        case ...0.75: return .mid
        default:      return .outer
        }
    }

    public static func < (lhs: RadialTier, rhs: RadialTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 방사형 그래프 노드 형상
public enum RadialNodeShape: String, Sendable, Codable {
    case circle
    case roundedRectangle
}

/// 순수 기하학 방사형 노드 데이터 모델 (도메인 비종속)
public struct RadialNode: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var label: String
    public var iconSystemName: String?
    public var distance: Double // 0.0 (중심) ~ 1.0 (최외곽)
    public var tier: RadialTier
    public var shape: RadialNodeShape
    public var tintHex: String?
    public var badge: String?
    public var size: Double

    public init(
        id: String,
        label: String,
        iconSystemName: String? = nil,
        distance: Double,
        tier: RadialTier? = nil,
        shape: RadialNodeShape = .circle,
        tintHex: String? = nil,
        badge: String? = nil,
        size: Double = 34.0
    ) {
        self.id = id
        self.label = label
        self.iconSystemName = iconSystemName
        self.distance = min(max(distance, 0.0), 1.0)
        self.tier = tier ?? RadialTier.tier(for: distance)
        self.shape = shape
        self.tintHex = tintHex
        self.badge = badge
        self.size = size
    }
}
