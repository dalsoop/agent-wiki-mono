import Crypto
import Foundation

/// 공유 원장 유틸 — content-addressing 의 기계적 뼈대.
/// KBW LedgerObject / forge ForgeObject 가 각자 재구현하던 것을 한 곳에 모은다.
public enum CitationLedger {

    /// content 주소 = 문자열의 SHA-256 hex(소문자). `id = sha256(canonicalCore)` 의 그 해시.
    public static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 본문 바이트의 SHA-256 hex — 하위호환 `sha256:` 필드(본문 변조 조기탐지)용.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 시간 (ms 정밀, 결정적 왕복)

    /// ms 정밀 ISO8601. content-hash id 는 무작위라 `(published, id)` 정렬의 유일한 시간 기준.
    /// ISO8601DateFormatter(고전 Foundation)는 ms 로 결정적 절단해 왕복이 안정적이다
    /// (Date.ISO8601FormatStyle 의 반올림 편차 회피). Linux Foundation 에서도 동작.
    nonisolated(unsafe) public static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 초 정밀 ISO8601 — v1 객체(분수 없는) 파싱 폴백.
    nonisolated(unsafe) public static let iso = ISO8601DateFormatter()

    /// 직렬화용 — 항상 ms 정밀.
    public static func string(from date: Date) -> String {
        isoFraction.string(from: date)
    }

    /// 파싱 — ms 우선, 없으면 초 정밀 폴백.
    public static func date(from raw: String) -> Date? {
        isoFraction.date(from: raw) ?? iso.date(from: raw)
    }

    // MARK: - UUIDv7 (실행 식별자 — batch/session 용, 객체 id 아님)

    /// UUIDv7 — 시간순 정렬 내장(unix ms 48bit + rand). 객체 id 는 content-addressed 지만
    /// batch/session 같은 **실행 식별자**는 시간순 UUIDv7 이 적합하다.
    public static func uuidV7(now: Date = Date()) -> String {
        let ms = UInt64(now.timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<6 { bytes[i] = UInt8((ms >> (8 * UInt64(5 - i))) & 0xFF) }
        for i in 6..<16 { bytes[i] = UInt8.random(in: 0...255) }
        bytes[6] = (bytes[6] & 0x0F) | 0x70  // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        var s = hex
        for offset in [8, 13, 18, 23] {
            s.insert("-", at: s.index(s.startIndex, offsetBy: offset))
        }
        return s
    }
}
