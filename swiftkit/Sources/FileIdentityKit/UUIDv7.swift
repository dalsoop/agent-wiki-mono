import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// RFC 9562 표준 UUIDv7 (Section 5.7).
///
/// 구조 (128비트, 16바이트):
/// - 상위 48비트: Unix epoch 밀리초 타임스탬프 (`unix_ts_ms`)
/// - 4비트: 버전 7 (`0111`)
/// - 12비트: 시퀀스 / 난수 (`rand_a`)
/// - 2비트: 변형 (`10` - Variant 1, RFC 4122/9562)
/// - 62비트: 난수 (`rand_b`)
///
/// 단조 증가(monotonicity):
/// 동일 밀리초 내 연속 생성 시 12비트 시퀀스 카운터를 단조 증가시키며,
/// 카운터 소진(4,096건 초과) 또는 시계 역행 시 가상 타임스탬프를 1ms 전진시켜
/// 시계열 역전 및 충돌을 원천 차단합니다.
public struct UUIDv7: Sendable, Comparable, Hashable, Codable, CustomStringConvertible, LosslessStringConvertible, Identifiable {
    public typealias RawBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    public typealias RandomBytes10 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    public typealias RandomBytes16 = RawBytes

    /// 상위 64비트:
    /// - bits 63..16 (48-bit): unix_ts_ms
    /// - bits 15..12 (4-bit): ver (0x7)
    /// - bits 11..0  (12-bit): rand_a / monotonic sequence
    public let high: UInt64

    /// 하위 64비트:
    /// - bits 63..62 (2-bit): var (0b10)
    /// - bits 61..0  (62-bit): rand_b
    public let low: UInt64

    public var id: UUIDv7 { self }

    // MARK: - Initializers

    /// 현재 시각 기반 단조 증가(monotonic) UUIDv7 생성.
    public init() {
        let (h, l) = MonotonicGenerator.shared.next()
        self.high = h
        self.low = l
    }

    /// 내부 64비트 정수 쌍 직접 초기화.
    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// RFC 9562 지정 타임스탬프 및 10바이트 난수/시퀀스 버퍼로 초기화.
    ///
    /// - Parameters:
    ///   - timestamp: Unix epoch 밀리초 (하위 48비트 사용)
    ///   - randomBytes: 10바이트 난수 튜플 (rand_a 12비트 + rand_b 62비트로 분할 주입)
    public init(timestamp: UInt64, randomBytes: RandomBytes10) {
        let (r0, r1, r2, r3, r4, r5, r6, r7, r8, r9) = randomBytes
        self.high = ((timestamp & 0x0000_FFFF_FFFF_FFFF) << 16) |
                    0x7000 |
                    (UInt64(r0 & 0x0F) << 8) |
                    UInt64(r1)
        self.low = (UInt64(0x80 | (r2 & 0x3F)) << 56) |
                   (UInt64(r3) << 48) |
                   (UInt64(r4) << 40) |
                   (UInt64(r5) << 32) |
                   (UInt64(r6) << 24) |
                   (UInt64(r7) << 16) |
                   (UInt64(r8) << 8)  |
                   UInt64(r9)
    }

    /// RFC 9562 지정 타임스탬프 및 16바이트 버퍼(후반 10바이트 추출)로 초기화.
    public init(timestamp: UInt64, randomBytes: RandomBytes16) {
        let r10: RandomBytes10 = (
            randomBytes.6, randomBytes.7, randomBytes.8, randomBytes.9,
            randomBytes.10, randomBytes.11, randomBytes.12, randomBytes.13,
            randomBytes.14, randomBytes.15
        )
        self.init(timestamp: timestamp, randomBytes: r10)
    }

    /// 타임스탬프, 12비트 시퀀스, 62비트 난수 직접 지정 초기화.
    public init(timestamp: UInt64, sequence: UInt16 = 0, randB: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.high = ((timestamp & 0x0000_FFFF_FFFF_FFFF) << 16) |
                    0x7000 |
                    UInt64(sequence & 0x0FFF)
        self.low = (0x8000_0000_0000_0000) | (randB & 0x3FFF_FFFF_FFFF_FFFF)
    }

    /// 타임스탬프 기반 초기화 (시퀀스 및 rand_b는 암호학적 난수).
    public init(timestamp: UInt64) {
        let randA = UInt16.random(in: 0...0x0FFF)
        let randB = UInt64.random(in: 0...UInt64.max)
        self.init(timestamp: timestamp, sequence: randA, randB: randB)
    }

    /// Date 기반 초기화.
    public init(date: Date) {
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000.0).rounded())
        self.init(timestamp: ms)
    }

    /// 원시 16바이트 튜플 기반 초기화.
    public init(rawBytes: RawBytes) {
        self.high = (UInt64(rawBytes.0) << 56) |
                    (UInt64(rawBytes.1) << 48) |
                    (UInt64(rawBytes.2) << 40) |
                    (UInt64(rawBytes.3) << 32) |
                    (UInt64(rawBytes.4) << 24) |
                    (UInt64(rawBytes.5) << 16) |
                    (UInt64(rawBytes.6) << 8)  |
                    UInt64(rawBytes.7)
        self.low  = (UInt64(rawBytes.8) << 56) |
                    (UInt64(rawBytes.9) << 48) |
                    (UInt64(rawBytes.10) << 40) |
                    (UInt64(rawBytes.11) << 32) |
                    (UInt64(rawBytes.12) << 24) |
                    (UInt64(rawBytes.13) << 16) |
                    (UInt64(rawBytes.14) << 8)  |
                    UInt64(rawBytes.15)
    }

    /// Foundation `UUID` 상호 변환 생성자.
    public init(uuid: UUID) {
        let t = uuid.uuid
        self.init(rawBytes: (
            t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
            t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15
        ))
    }

    // MARK: - String Parsing & Formatting

    /// 표준 36자리 하이픈 UUID 문자열 파싱 (`init?(uuidString:)`).
    ///
    /// 버전 7 및 변형 1(0b10) 유효성을 함께 검증합니다.
    public init?(uuidString: String) {
        let utf8 = uuidString.utf8
        guard utf8.count == 36 else { return nil }

        var parsedHigh: UInt64 = 0
        var parsedLow: UInt64 = 0

        let parseBlock: (UnsafeBufferPointer<UInt8>) -> Bool = { ptr in
            guard ptr.count == 36 else { return false }
            let base = ptr.baseAddress!

            // 하이픈 위치 확인: 8, 13, 18, 23
            guard base[8] == 0x2D, base[13] == 0x2D, base[18] == 0x2D, base[23] == 0x2D else {
                return false
            }

            @inline(__always)
            func hexByte(_ at: Int) -> UInt8? {
                let h = UUIDv7.hexDecodeTable[Int(base[at])]
                let l = UUIDv7.hexDecodeTable[Int(base[at + 1])]
                guard h >= 0 && l >= 0 else { return nil }
                return (UInt8(h) << 4) | UInt8(l)
            }

            guard let b0 = hexByte(0),
                  let b1 = hexByte(2),
                  let b2 = hexByte(4),
                  let b3 = hexByte(6),
                  let b4 = hexByte(9),
                  let b5 = hexByte(11),
                  let b6 = hexByte(14),
                  let b7 = hexByte(16),
                  let b8 = hexByte(19),
                  let b9 = hexByte(21),
                  let b10 = hexByte(24),
                  let b11 = hexByte(26),
                  let b12 = hexByte(28),
                  let b13 = hexByte(30),
                  let b14 = hexByte(32),
                  let b15 = hexByte(34) else {
                return false
            }

            // 버전 7 확인 (byte 6 상위 4비트 == 7)
            guard (b6 >> 4) == 7 else { return false }
            // 변형 1 확인 (byte 8 상위 2비트 == 0b10)
            guard (b8 >> 6) == 2 else { return false }

            parsedHigh = (UInt64(b0) << 56) |
                         (UInt64(b1) << 48) |
                         (UInt64(b2) << 40) |
                         (UInt64(b3) << 32) |
                         (UInt64(b4) << 24) |
                         (UInt64(b5) << 16) |
                         (UInt64(b6) << 8)  |
                         UInt64(b7)

            parsedLow  = (UInt64(b8) << 56) |
                         (UInt64(b9) << 48) |
                         (UInt64(b10) << 40) |
                         (UInt64(b11) << 32) |
                         (UInt64(b12) << 24) |
                         (UInt64(b13) << 16) |
                         (UInt64(b14) << 8)  |
                         UInt64(b15)
            return true
        }

        let success = utf8.withContiguousStorageIfAvailable(parseBlock) ?? {
            let bytes = Array(utf8)
            return bytes.withUnsafeBufferPointer(parseBlock)
        }()

        guard success else { return nil }
        self.high = parsedHigh
        self.low = parsedLow
    }

    /// `LosslessStringConvertible` 적합성.
    public init?(_ description: String) {
        self.init(uuidString: description)
    }

    /// 표준 36자리 소문자 하이픈 UUID 문자열 (`xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx`).
    public var uuidString: String {
        var buffer = [UInt8](repeating: 0, count: 36)
        buffer.withUnsafeMutableBufferPointer { ptr in
            let base = ptr.baseAddress!

            @inline(__always)
            func writeHex(byte: UInt8, at: Int) {
                base[at] = UUIDv7.hexEncodeTable[Int(byte >> 4)]
                base[at + 1] = UUIDv7.hexEncodeTable[Int(byte & 0x0F)]
            }

            writeHex(byte: UInt8((high >> 56) & 0xFF), at: 0)
            writeHex(byte: UInt8((high >> 48) & 0xFF), at: 2)
            writeHex(byte: UInt8((high >> 40) & 0xFF), at: 4)
            writeHex(byte: UInt8((high >> 32) & 0xFF), at: 6)
            base[8] = 0x2D // '-'

            writeHex(byte: UInt8((high >> 24) & 0xFF), at: 9)
            writeHex(byte: UInt8((high >> 16) & 0xFF), at: 11)
            base[13] = 0x2D // '-'

            writeHex(byte: UInt8((high >> 8) & 0xFF), at: 14)
            writeHex(byte: UInt8(high & 0xFF), at: 16)
            base[18] = 0x2D // '-'

            writeHex(byte: UInt8((low >> 56) & 0xFF), at: 19)
            writeHex(byte: UInt8((low >> 48) & 0xFF), at: 21)
            base[23] = 0x2D // '-'

            writeHex(byte: UInt8((low >> 40) & 0xFF), at: 24)
            writeHex(byte: UInt8((low >> 32) & 0xFF), at: 26)
            writeHex(byte: UInt8((low >> 24) & 0xFF), at: 28)
            writeHex(byte: UInt8((low >> 16) & 0xFF), at: 30)
            writeHex(byte: UInt8((low >> 8) & 0xFF), at: 32)
            writeHex(byte: UInt8(low & 0xFF), at: 34)
        }
        return String(decoding: buffer, as: UTF8.self)
    }

    public var description: String {
        uuidString
    }

    // MARK: - Foundation UUID Conversion

    /// Foundation `UUID`로 변환.
    public func toUUID() -> UUID {
        let b = rawBytes
        let uuidT: uuid_t = (
            b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
            b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15
        )
        return UUID(uuid: uuidT)
    }

    // MARK: - Field Accessors

    /// 48비트 Unix epoch 밀리초 타임스탬프.
    public var timestamp: UInt64 {
        high >> 16
    }

    /// 타임스탬프 기준 Date 인스턴스.
    public var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }

    /// 버전 번호 (UUIDv7의 경우 항상 7).
    public var version: Int {
        Int((high >> 12) & 0x0F)
    }

    /// 12비트 시퀀스 카운터 / rand_a.
    public var sequence: UInt16 {
        UInt16(high & 0x0FFF)
    }

    /// 변형 비트 (RFC 4122/9562 표준의 경우 2 = 0b10).
    public var variant: Int {
        Int((low >> 62) & 0x03)
    }

    /// 원시 16바이트 튜플.
    public var rawBytes: RawBytes {
        (
            UInt8((high >> 56) & 0xFF),
            UInt8((high >> 48) & 0xFF),
            UInt8((high >> 40) & 0xFF),
            UInt8((high >> 32) & 0xFF),
            UInt8((high >> 24) & 0xFF),
            UInt8((high >> 16) & 0xFF),
            UInt8((high >> 8) & 0xFF),
            UInt8(high & 0xFF),
            UInt8((low >> 56) & 0xFF),
            UInt8((low >> 48) & 0xFF),
            UInt8((low >> 40) & 0xFF),
            UInt8((low >> 32) & 0xFF),
            UInt8((low >> 24) & 0xFF),
            UInt8((low >> 16) & 0xFF),
            UInt8((low >> 8) & 0xFF),
            UInt8(low & 0xFF)
        )
    }

    /// Foundation.UUID와의 호환을 위한 `uuid` 프로퍼티.
    public var uuid: uuid_t {
        rawBytes
    }

    // MARK: - Convenience Static Generator

    /// 빠른 문자열 생성 편의 API.
    public static func generate() -> String {
        UUIDv7().uuidString
    }

    // MARK: - Comparable & Hashable

    public static func < (lhs: UUIDv7, rhs: UUIDv7) -> Bool {
        if lhs.high != rhs.high {
            return lhs.high < rhs.high
        }
        return lhs.low < rhs.low
    }

    public static func == (lhs: UUIDv7, rhs: UUIDv7) -> Bool {
        lhs.high == rhs.high && lhs.low == rhs.low
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(high)
        hasher.combine(low)
    }

    // MARK: - Codable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuidString)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = UUIDv7(uuidString: string) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid UUIDv7 string: \(string)"
                )
            )
        }
        self = parsed
    }

    // MARK: - Lookup Tables

    private static let hexEncodeTable: [UInt8] = [
        0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66
    ]

    private static let hexDecodeTable: [Int8] = {
        var table = [Int8](repeating: -1, count: 256)
        for c in UInt8(ascii: "0")...UInt8(ascii: "9") {
            table[Int(c)] = Int8(c - UInt8(ascii: "0"))
        }
        for c in UInt8(ascii: "a")...UInt8(ascii: "f") {
            table[Int(c)] = Int8(c - UInt8(ascii: "a") + 10)
        }
        for c in UInt8(ascii: "A")...UInt8(ascii: "F") {
            table[Int(c)] = Int8(c - UInt8(ascii: "A") + 10)
        }
        return table
    }()
}

// MARK: - Thread-Safe Monotonic Generator

private final class MonotonicGenerator: @unchecked Sendable {
    static let shared = MonotonicGenerator()

    private let lock = NSLock()
    private var lastTimestamp: UInt64 = 0
    private var sequence: UInt16 = 0

    private init() {}

    func next() -> (high: UInt64, low: UInt64) {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        let ms = UInt64(ts.tv_sec) &* 1000 &+ UInt64(ts.tv_nsec / 1_000_000)

        lock.lock()
        let currentTs: UInt64
        let currentSeq: UInt16

        if ms > lastTimestamp {
            lastTimestamp = ms
            sequence = 0
        } else {
            // 동일 밀리초 내 또는 시계 역행 발생 시 단조 증가 보장
            if sequence < 0x0FFF {
                sequence &+= 1
            } else {
                // 12비트 시퀀스(4096개) 소진 시 가상 타임스탬프 1ms 전진
                lastTimestamp &+= 1
                sequence = 0
            }
        }
        currentTs = lastTimestamp
        currentSeq = sequence
        lock.unlock()

        let high = ((currentTs & 0x0000_FFFF_FFFF_FFFF) << 16) | 0x7000 | UInt64(currentSeq & 0x0FFF)
        let randB = UInt64.random(in: 0...UInt64.max)
        let low = (0x8000_0000_0000_0000) | (randB & 0x3FFF_FFFF_FFFF_FFFF)

        return (high, low)
    }
}
