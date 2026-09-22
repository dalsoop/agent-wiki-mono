import Foundation

/// CRC-32(IEEE 802.3, zip 표준 다항식 0xEDB88320) — 외부 의존 없이 zip local/central header 의
/// crc-32 필드를 채우기 위한 최소 구현. 룩업 테이블은 최초 접근 시 1회만 계산된다.
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
