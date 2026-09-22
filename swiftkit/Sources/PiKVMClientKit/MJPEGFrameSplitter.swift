import Foundation

/// `multipart/x-mixed-replace` 스트림에서 JPEG 프레임을 잘라낸다.
///
/// URLSession 은 multipart 를 풀어주지 않는다. 그런데 경계 문자열은 설치본마다 다르고
/// (실측 PiKVM 4.121 은 `--boundarydonotcross`), 헤더 구성도 제각각이다. 그래서 경계 대신
/// **JPEG 자체의 SOI(FFD8)/EOI(FFD9)** 를 훑는다 — 경계 표기가 무엇이든 프레임을 놓치지 않고,
/// 부분 수신(한 프레임이 여러 콜백에 걸쳐 도착)도 자연스럽게 처리된다.
///
/// 실측 확인: 위 스트림에서 뽑은 첫 프레임 길이가 `Content-Length: 22323` 과 정확히 일치했다.
public struct MJPEGFrameSplitter: Sendable {
    /// 한 프레임이 이보다 커지면 스트림이 깨진 것으로 보고 버린다(무한 증가 방지).
    public let maxBufferBytes: Int
    private var buffer = Data()

    public init(maxBufferBytes: Int = 24 * 1024 * 1024) {
        self.maxBufferBytes = maxBufferBytes
    }

    public var bufferedByteCount: Int { buffer.count }

    /// 새로 받은 바이트를 넣고, 완성된 프레임을 **도착 순서대로** 돌려준다.
    /// 한 번의 콜백에 여러 프레임이 들어올 수 있어 배열이다.
    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        if buffer.count > maxBufferBytes { buffer.removeAll(keepingCapacity: false) }

        var frames: [Data] = []
        while let frame = Self.extractFrame(from: &buffer) {
            frames.append(frame)
        }
        return frames
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    /// 버퍼 앞쪽에서 완성된 JPEG 한 장을 잘라낸다. 없으면 nil (버퍼는 보존한다 —
    /// 아직 덜 온 프레임을 버리면 매번 한 장씩 잃는다).
    static func extractFrame(from buffer: inout Data) -> Data? {
        guard let start = buffer.firstIndex(ofPattern: [0xFF, 0xD8]) else {
            // SOI 가 아직 없다 = 지금까지 온 건 전부 멀티파트 헤더나 잡음이다. 버린다.
            // 다만 마지막 1바이트는 남긴다 — 0xFF 와 0xD8 이 청크 경계에 걸쳐 오면
            // 여기서 통째로 버리는 순간 그 프레임을 영영 못 찾는다.
            if buffer.count > 1 {
                buffer.removeSubrange(buffer.startIndex..<(buffer.endIndex - 1))
            }
            return nil
        }
        guard let end = buffer.firstIndex(ofPattern: [0xFF, 0xD9], from: start + 2) else {
            // 프레임이 아직 덜 왔다. SOI 앞의 멀티파트 헤더만 걷어내고 나머지는 기다린다 —
            // 여기서 버리면 매 프레임 한 장씩 잃는다.
            if start > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start) }
            return nil
        }
        let frameEnd = end + 2
        let frame = Data(buffer[start..<frameEnd])
        buffer.removeSubrange(buffer.startIndex..<frameEnd)
        return frame
    }
}

extension Data {
    /// 바이트 패턴의 첫 위치. `Data.range(of:)` 는 플랫폼별 성능 편차가 커 직접 훑는다.
    func firstIndex(ofPattern pattern: [UInt8], from offset: Int? = nil) -> Int? {
        guard !pattern.isEmpty, count >= pattern.count else { return nil }
        // Data 의 인덱스는 0 부터가 아닐 수 있다(슬라이스). 항상 startIndex 기준으로 센다.
        let begin = Swift.max(offset ?? startIndex, startIndex)
        let last = endIndex - pattern.count
        guard begin <= last else { return nil }
        var i = begin
        while i <= last {
            var matched = true
            for (k, byte) in pattern.enumerated() where self[i + k] != byte {
                matched = false
                break
            }
            if matched { return i }
            i += 1
        }
        return nil
    }
}
