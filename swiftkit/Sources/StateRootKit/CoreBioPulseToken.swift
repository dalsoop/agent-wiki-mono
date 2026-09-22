import Foundation

/// 하네스 2선 런타임 토큰 — 코어 생체 틱과 불투명 서명을 바인딩하여 펄스 위조 방지
public struct CoreBioPulseToken: Sendable, Equatable, Codable {
    public let tick: Int64
    public let signature: UInt64

    public init(tick: Int64, signature: UInt64) {
        self.tick = tick
        self.signature = signature
    }

    /// 틱 번호와 시크릿/솔트를 기반으로 런타임 토큰을 생성
    public static func make(tick: Int64, salt: UInt64 = 0x544F_4B45_4E5F_5345) -> CoreBioPulseToken {
        var hasher = Hasher()
        hasher.combine(tick)
        hasher.combine(salt)
        let hashValue = UInt64(bitPattern: Int64(hasher.finalize()))
        return CoreBioPulseToken(tick: tick, signature: hashValue)
    }

    /// 토큰의 서명이 일치하는지 검증
    public func isValid(for expectedTick: Int64, salt: UInt64 = 0x544F_4B45_4E5F_5345) -> Bool {
        guard tick == expectedTick else { return false }
        return self == Self.make(tick: expectedTick, salt: salt)
    }
}
